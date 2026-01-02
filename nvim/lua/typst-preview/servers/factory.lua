local fetch = require("typst-preview.fetch")
local utils = require("typst-preview.utils")
local config = require("typst-preview.config")

-- Responsible for starting, stopping and communicating with the server
local M = {}

local function ipv4_to_u32(ip)
  if type(ip) ~= "string" then
    return nil
  end
  local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then
    return nil
  end
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if not (a and b and c and d) or a > 255 or b > 255 or c > 255 or d > 255 then
    return nil
  end
  return a * 2 ^ 24 + b * 2 ^ 16 + c * 2 ^ 8 + d
end

local function is_cgnat_100_64_10(ip)
  local n = ipv4_to_u32(ip)
  if not n then
    return false
  end
  local lo = 100 * 2 ^ 24 + 64 * 2 ^ 16 + 0 * 2 ^ 8 + 0 -- 100.64.0.0
  local hi = 100 * 2 ^ 24 + 127 * 2 ^ 16 + 255 * 2 ^ 8 + 255 -- 100.127.255.255
  return n >= lo and n <= hi
end

-- Normalize uv.interface_addresses() to iterate {name,family,internal,ip}
local function iter_iface_records(ifs)
  if type(ifs) ~= "table" then
    return function()
      return nil
    end
  end

  -- Case A: array
  if #ifs > 0 then
    local i = 0
    return function()
      i = i + 1
      local it = ifs[i]
      if not it then
        return nil
      end
      return {
        name = it.name or "",
        family = it.family or it.address_family,
        internal = it.internal or it.is_internal or false,
        ip = it.address or it.addr or it.ip or it.ip_address,
      }
    end
  end

  -- Case B: map[name] -> {records...}
  local next_if, tbl, k = next, ifs, nil
  local name, list, j = nil, nil, 0

  local function advance()
    k, list = next_if(tbl, k)
    j = 0
    name = k
    return k ~= nil
  end
  advance()

  return function()
    while name do
      j = j + 1
      local rec = list and list[j]
      if rec then
        return {
          name = name or "",
          family = rec.family or rec.address_family,
          internal = rec.internal or rec.is_internal or false,
          ip = rec.address or rec.addr or rec.ip or rec.ip_address,
        }
      end
      if not advance() then
        return nil
      end
    end
    return nil
  end
end

local function select_bind_ip()
  local uv = vim.uv or vim.loop
  if not (uv and uv.interface_addresses) then
    return "127.0.0.1"
  end
  local ok, ifs = pcall(uv.interface_addresses)
  if not ok then
    return "127.0.0.1"
  end

  for rec in iter_iface_records(ifs) do
    local fam = rec.family
    local is_ipv4 = (fam == "inet" or fam == "IPv4" or fam == 2)
    if is_ipv4 and not rec.internal and type(rec.ip) == "string" and is_cgnat_100_64_10(rec.ip) then
      return rec.ip
    end
  end
  return "127.0.0.1"
end

---Spawn the server and connect to it using the websocat process
---@param path string
---@param mode mode
---@param callback fun(close: fun(), write: fun(data: string), read: fun(on_read: fun(data: string)), link: string)
---Called after server spawn completes
local function spawn(path, port, mode, callback)
  local server_stdout = assert(vim.uv.new_pipe())
  local server_stderr = assert(vim.uv.new_pipe())
  local tinymist_bin = config.opts.dependencies_bin["tinymist"]
    or (utils.get_data_path() .. fetch.get_tinymist_bin_name())
  local bind_ip = select_bind_ip()
  vim.notify("Tinymist serving at " .. bind_ip)

  local args = {
    "preview",
    "--invert-colors",
    config.opts.invert_colors,
    "--preview-mode",
    mode,
    "--no-open",

    -- Use chosen bind_ip instead of 0.0.0.0
    "--data-plane-host",
    bind_ip .. ":0",
    "--control-plane-host",
    bind_ip .. ":0",
    "--static-file-host",
    bind_ip .. ":" .. port,

    "--root",
    config.opts.get_root(path),
  }

  if config.opts.extra_args ~= nil then
    for _, v in ipairs(config.opts.extra_args) do
      table.insert(args, v)
    end
  end

  table.insert(args, config.opts.get_main_file(path))

  local server_handle, _ = assert(vim.uv.spawn(tinymist_bin, {
    args = args,
    stdio = { nil, server_stdout, server_stderr },
  }))
  utils.debug("spawning server " .. tinymist_bin .. " with args:")
  utils.debug(vim.inspect(args))

  -- This will be gradually filled util it's ready to be fed to callback
  -- Refactor if there's a third place callback would be called.
  ---@type { close: fun(), write: fun(data: string), read: fun(on_read: fun(data: string)) } | string | nil
  local callback_param = nil

  local function connect(host)
    local stdin = assert(vim.uv.new_pipe())
    local stdout = assert(vim.uv.new_pipe())
    local stderr = assert(vim.uv.new_pipe())
    local addr = "ws://" .. host .. "/"
    local websocat_bin = config.opts.dependencies_bin["websocat"]
      or (utils.get_data_path() .. fetch.get_websocat_bin_name())
    local websocat_handle, _ = assert(vim.uv.spawn(websocat_bin, {
      args = {
        "-B",
        "10000000",
        "--origin",
        "http://localhost",
        addr,
      },
      stdio = { stdin, stdout, stderr },
    }))
    utils.debug("websocat connecting to: " .. addr)
    stderr:read_start(function(err, data)
      if err then
        error(err)
      elseif data then
        utils.debug("websocat error: " .. data)
      end
    end)

    local param = {
      close = function()
        websocat_handle:kill()
        server_handle:kill()
      end,
      write = function(data)
        stdin:write(data)
      end,
      read = function(on_read)
        stdout:read_start(function(err, data)
          if err then
            error(err)
          elseif data then
            utils.debug("websocat said: " .. data)
            on_read(data)
          end
        end)
      end,
    }
    if callback_param ~= nil then
      assert(type(callback_param) == "string", "callback_param isn't a string")
      callback(param.close, param.write, param.read, callback_param)
    else
      callback_param = param
    end
  end

  local function find_host(server_output, prompt)
    local _, s = server_output:find(prompt)
    if s then
      local e, _ = (server_output .. "\n"):find("\n", s + 1)
      return server_output:sub(s + 1, e - 1):gsub("%s+", "")
    end
  end

  local function read_server(serr, server_output)
    if serr then
      error(serr)
    end

    if not server_output then
      return
    end

    if server_output:find("AddrInUse") then
      print("Port " .. port .. " is already in use")
      server_stdout:close()
      server_stderr:close()
      -- try again at port + 1
      vim.defer_fn(function()
        spawn(path, port + 1, mode, callback)
      end, 0)
    end
    local control_host = find_host(server_output, "Control plane server listening on: ")
      or find_host(server_output, "Control panel server listening on: ")
    local static_host = find_host(server_output, "Static file server listening on: ")
    if control_host then
      utils.debug("Connecting to server")
      connect(control_host)
    end
    if static_host then
      utils.debug("Setting link")
      vim.defer_fn(function()
        utils.visit(static_host)
        if callback_param ~= nil then
          assert(
            type(callback_param.close) == "function"
              and type(callback_param.write) == "function"
              and type(callback_param.read) == "function",
            "callback_param's type isn't a table of functions"
          )
          callback(callback_param.close, callback_param.write, callback_param.read, static_host)
        else
          callback_param = static_host
        end
      end, 0)
    end
    utils.debug(server_output)
  end

  server_stdout:read_start(read_server)
  server_stderr:read_start(read_server)
end

---create a new Server
---@param path string
---@param mode mode
---@param callback fun(server: Server)
function M.new(path, mode, callback)
  local read_buffer = ""

  spawn(path, config.opts.port, mode, function(close, write, read, link)
    ---@type Server
    local server = {
      path = path,
      mode = mode,
      link = link,
      suppress = false,
      close = close,
      write = write,
      listenerss = {},
    }

    read(function(data)
      vim.defer_fn(function()
        read_buffer = read_buffer .. data
        local s, _ = read_buffer:find("\n")
        while s ~= nil do
          local event = assert(vim.json.decode(read_buffer:sub(1, s - 1)))

          -- Make sure we keep the next message in the read buffer
          read_buffer = read_buffer:sub(s + 1, -1)
          s, _ = read_buffer:find("\n")

          local listeners = server.listenerss[event.event]
          if listeners ~= nil then
            for _, listener in pairs(listeners) do
              listener(event)
            end
          end
        end

        if read_buffer ~= "" then
          utils.debug("Leaving for next read: " .. read_buffer)
        end
      end, 0)
    end)

    callback(server)
  end)
end

return M
