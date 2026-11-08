# Nixvim module (not a Home Manager module) with the development profile's
# keymaps.
{
  keymaps = [
    {
      mode = "n";
      key = "<A-j>";
      action = "<cmd>execute 'move .+' . v:count1<cr>==";
      options.desc = "Move Down";
    }
    {
      mode = "n";
      key = "<A-k>";
      action = "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==";
      options.desc = "Move Up";
    }
    {
      mode = "i";
      key = "<A-j>";
      action = "<esc><cmd>m .+1<cr>==gi";
      options.desc = "Move Down";
    }
    {
      mode = "i";
      key = "<A-k>";
      action = "<esc><cmd>m .-2<cr>==gi";
      options.desc = "Move Up";
    }
    {
      mode = "v";
      key = "<A-j>";
      action = ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv";
      options.desc = "Move Down";
    }
    {
      mode = "v";
      key = "<A-k>";
      action = ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv";
      options.desc = "Move Up";
    }
    {
      mode = "n";
      key = "<S-h>";
      action = "<cmd>BufferLineCyclePrev<cr>";
      options.desc = "Prev Buffer";
    }
    {
      mode = "n";
      key = "<S-l>";
      action = "<cmd>BufferLineCycleNext<cr>";
      options.desc = "Next Buffer";
    }
    {
      mode = "n";
      key = "<leader>bd";
      action.__raw = ''
        function()
          local current, alternate = vim.api.nvim_get_current_buf(), vim.fn.bufnr("#")
          vim.cmd(alternate > 0 and vim.api.nvim_buf_is_loaded(alternate) and "buffer #" or "bnext")
          vim.cmd("bdelete " .. current)
        end
      '';
      options.desc = "Delete Buffer";
    }
    {
      mode = "n";
      key = "<leader>bo";
      action.__raw = ''
        function()
          local current = vim.api.nvim_get_current_buf()
          for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buffer) and buffer ~= current then vim.cmd("bdelete " .. buffer) end
          end
        end
      '';
      options.desc = "Delete Other Buffers";
    }
    {
      mode = "n";
      key = "<leader>bD";
      action = "<cmd>bd<cr>";
      options.desc = "Delete Buffer and Window";
    }
    {
      mode = "n";
      key = "<leader>bp";
      action = "<cmd>BufferLineTogglePin<cr>";
      options.desc = "Toggle Pin";
    }
    {
      mode = "n";
      key = "<leader>bP";
      action = "<cmd>BufferLineGroupClose ungrouped<cr>";
      options.desc = "Delete Non-Pinned Buffers";
    }
    {
      mode = "n";
      key = "<leader><space>";
      action = "<cmd>Telescope find_files<cr>";
      options.desc = "Find files";
    }
    {
      mode = "n";
      key = "<leader>/";
      action = "<cmd>Telescope live_grep<cr>";
      options.desc = "Grep in files";
    }
    {
      mode = "n";
      key = "<leader>,";
      action = "<cmd>Telescope buffers sort_mru=true sort_lastused=true ignore_current_buffer=true<cr>";
      options.desc = "Switch buffers";
    }
    {
      mode = "n";
      key = "<leader>:";
      action = "<cmd>Telescope command_history<cr>";
      options.desc = "Command History";
    }
    {
      mode = "n";
      key = "n";
      action = "'Nn'[v:searchforward].'zv'";
      options = {
        expr = true;
        desc = "Next Search Result";
      };
    }
    {
      mode = [
        "x"
        "o"
      ];
      key = "n";
      action = "'Nn'[v:searchforward]";
      options = {
        expr = true;
        desc = "Next Search Result";
      };
    }
    {
      mode = "n";
      key = "N";
      action = "'nN'[v:searchforward].'zv'";
      options = {
        expr = true;
        desc = "Prev Search Result";
      };
    }
    {
      mode = [
        "x"
        "o"
      ];
      key = "N";
      action = "'nN'[v:searchforward]";
      options = {
        expr = true;
        desc = "Prev Search Result";
      };
    }
    {
      mode = "n";
      key = "<leader>e";
      action.__raw = "function() require('neo-tree.command').execute({ toggle = true, dir = vim.uv.cwd() }) end";
      options.desc = "Explorer NeoTree (cwd)";
    }
    {
      mode = "n";
      key = "<leader>cf";
      action.__raw = "function() require('conform').format({ async = true, lsp_format = 'fallback', timeout_ms = 500 }) end";
      options.desc = "Format file";
    }
    {
      mode = "n";
      key = "<leader>ca";
      action.__raw = "function() require('tiny-code-action').code_action() end";
      options.desc = "Code Action";
    }
    {
      mode = "n";
      key = "<leader>cd";
      action.__raw = "vim.diagnostic.open_float";
      options.desc = "Line Diagnostics";
    }
    {
      mode = "n";
      key = "<leader>xl";
      action.__raw = ''
        function()
          local open = vim.fn.getloclist(0, { winid = 0 }).winid ~= 0
          local ok, err = pcall(open and vim.cmd.lclose or vim.cmd.lopen)
          if not ok then vim.notify(err, vim.log.levels.ERROR) end
        end
      '';
      options.desc = "Location List";
    }
    {
      mode = "n";
      key = "<leader>xq";
      action.__raw = ''
        function()
          local open = vim.fn.getqflist({ winid = 0 }).winid ~= 0
          local ok, err = pcall(open and vim.cmd.cclose or vim.cmd.copen)
          if not ok then vim.notify(err, vim.log.levels.ERROR) end
        end
      '';
      options.desc = "Quickfix List";
    }
    {
      mode = "n";
      key = "]d";
      action.__raw = "function() vim.diagnostic.jump({ count = vim.v.count1, float = true }) end";
      options.desc = "Next Diagnostic";
    }
    {
      mode = "n";
      key = "[d";
      action.__raw = "function() vim.diagnostic.jump({ count = -vim.v.count1, float = true }) end";
      options.desc = "Prev Diagnostic";
    }
    {
      mode = "n";
      key = "]e";
      action.__raw = "function() vim.diagnostic.jump({ count = vim.v.count1, severity = vim.diagnostic.severity.ERROR, float = true }) end";
      options.desc = "Next Error";
    }
    {
      mode = "n";
      key = "[e";
      action.__raw = "function() vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.ERROR, float = true }) end";
      options.desc = "Prev Error";
    }
    {
      mode = "n";
      key = "]w";
      action.__raw = "function() vim.diagnostic.jump({ count = vim.v.count1, severity = vim.diagnostic.severity.WARN, float = true }) end";
      options.desc = "Next Warning";
    }
    {
      mode = "n";
      key = "[w";
      action.__raw = "function() vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.WARN, float = true }) end";
      options.desc = "Prev Warning";
    }
    {
      mode = "n";
      key = "[q";
      action = "<cmd>cprev<cr>";
      options.desc = "Previous Quickfix";
    }
    {
      mode = "n";
      key = "]q";
      action = "<cmd>cnext<cr>";
      options.desc = "Next Quickfix";
    }
    {
      mode = "n";
      key = "<leader>K";
      action = "<cmd>norm! K<cr>";
      options.desc = "Keywordprg";
    }
    {
      mode = "n";
      key = "gco";
      action = "o<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>";
      options.desc = "Add Comment Below";
    }
    {
      mode = "n";
      key = "gcO";
      action = "O<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>";
      options.desc = "Add Comment Above";
    }
    {
      mode = "n";
      key = "<leader>fn";
      action = "<cmd>enew<cr>";
      options.desc = "New File";
    }
    {
      mode = "n";
      key = "<leader>qq";
      action = "<cmd>qa<cr>";
      options.desc = "Quit All";
    }
    {
      mode = "t";
      key = "<A-q>";
      action = "<C-\\><C-n>";
      options = {
        desc = "Escape terminal mode";
        remap = true;
      };
    }
    {
      mode = "n";
      key = "<leader>?";
      action.__raw = "function() require('which-key').show({ global = false }) end";
      options.desc = "Buffer Local Keymaps";
    }
  ];
}
