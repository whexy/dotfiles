# Full development Nixvim profile. Language integrations live in their
# corresponding editor language modules.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.editor;
in
{
  config = lib.mkIf (cfg.neovim.enable && cfg.neovim.dev) {
    programs.nixvim = {
      opts = {
        exrc = true;
        secure = true;
        textwidth = 80;
        colorcolumn = "80";
        winminwidth = 5;
        list = false;
        foldtext = "v:lua.vim.fn.getline(v:foldstart) .. ' ...'";
        jumpoptions = "view";
      };

      colorschemes.gruvbox.enable = true;

      plugins = {
        nui.enable = true;
        web-devicons.enable = true;
        lualine.enable = true;
        bufferline = {
          enable = true;
          settings.options = {
            close_command.__raw = "function(bufnr) vim.cmd('bdelete ' .. bufnr) end";
            right_mouse_command.__raw = "function(bufnr) vim.cmd('bdelete ' .. bufnr) end";
            diagnostics = "nvim_lsp";
            always_show_bufferline = true;
            diagnostics_indicator.__raw = ''
              function(_, _, diag)
                return (diag.error and " E" .. diag.error .. " " or "")
                  .. (diag.warning and " W" .. diag.warning or "")
              end
            '';
            offsets = [
              {
                filetype = "neo-tree";
                text = "Neo-tree";
                highlight = "Directory";
                text_align = "left";
              }
            ];
          };
        };
        neo-tree = {
          enable = true;
          settings = {
            source_selector.winbar = true;
            filesystem = {
              follow_current_file.enabled = true;
              filtered_items.visible = true;
              use_libuv_file_watcher = true;
            };
          };
        };
        which-key.enable = true;
        friendly-snippets.enable = true;
        blink-cmp = {
          enable = true;
          setupLspCapabilities = true;
          settings = {
            keymap.preset = "enter";
            appearance.nerd_font_variant = "mono";
            completion.documentation.auto_show = false;
            sources.default = [
              "lsp"
              "path"
              "snippets"
              "buffer"
            ];
            fuzzy.implementation = "lua";
          };
        };
        treesitter = {
          enable = true;
          highlight.enable = true;
          indent.enable = true;
          folding.enable = true;
          grammarPackages = with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [ regex ];
          languageRegister.markdown = "mdx";
        };
        treesitter-textobjects.enable = true;
        telescope.enable = true;
        flash.enable = true;
        mini-ai = {
          enable = true;
          settings = {
            n_lines = 500;
            custom_textobjects.__raw = ''
              (function()
                local ai = require("mini.ai")
                return {
                  o = ai.gen_spec.treesitter({
                    a = { "@block.outer", "@conditional.outer", "@loop.outer" },
                    i = { "@block.inner", "@conditional.inner", "@loop.inner" },
                  }),
                  f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
                  c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
                  t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" },
                  d = { "%f[%d]%d+" },
                  u = ai.gen_spec.function_call(),
                  U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
                }
              end)()
            '';
          };
        };
        mini-surround = {
          enable = true;
          settings.mappings = {
            add = "gsa";
            delete = "gsd";
            find = "gsf";
            find_left = "gsF";
            highlight = "gsh";
            replace = "gsr";
            update_n_lines = "gsn";
          };
        };
        yanky = {
          enable = true;
          settings.system_clipboard.sync_with_ring = false;
        };
        indent-blankline = {
          enable = true;
          settings = {
            indent = {
              char = "|";
              tab_char = "|";
            };
            scope = {
              show_start = false;
              show_end = false;
            };
            exclude.filetypes = [
              "help"
              "lazy"
              "mason"
            ];
          };
        };
        conform-nvim = {
          enable = true;
          autoInstall.enable = true;
          settings.format_on_save = {
            lsp_format = "fallback";
            timeout_ms = 500;
          };
        };
        lint = {
          enable = true;
          autoInstall.enable = true;
          autoCmd = {
            event = [
              "BufWritePost"
              "BufReadPost"
              "InsertLeave"
            ];
            callback.__raw = "function() require('lint').try_lint() end";
          };
        };
        tiny-inline-diagnostic = {
          enable = true;
          settings = {
            preset = "minimal";
            options.overwrite_events = [
              "LspAttach"
              "DiagnosticChanged"
            ];
          };
        };
        lspconfig.enable = true;
        firenvim = {
          enable = true;
          settings.localSettings.".*" = {
            takeover = "never";
            selector = ''textarea:not([readonly],[aria-readonly]),div[role="textbox"],[contenteditable="true"]'';
          };
        };
        hardtime.enable = true;
      };

      extraPlugins = with pkgs.vimPlugins; [
        refjump-nvim
        nvim-lsp-file-operations
        # Not packaged in nixpkgs; built from source.
        (pkgs.vimUtils.buildVimPlugin {
          pname = "tiny-code-action.nvim";
          version = "0d040ed";
          src = pkgs.fetchFromGitHub {
            owner = "rachartier";
            repo = "tiny-code-action.nvim";
            rev = "0d040ed81f7953118b81cd12681fcdfcac069803";
            hash = "sha256-UF9zeO5Uujdt2MEwy2d2Lhk6JRnEN4vrEvYslv0/zaA=";
          };
          dependencies = [ nui-nvim ];
          # Optional snacks.nvim previewer; snacks is not installed.
          nvimSkipModules = [ "tiny-code-action.previewers.snacks" ];
        })
      ];

      autoGroups = {
        editor_width.clear = true;
        lsp_setup.clear = true;
      };
      autoCmd = [
        {
          event = [ "FileType" ];
          pattern = [
            "rust"
            "zig"
          ];
          group = "editor_width";
          callback.__raw = "function() vim.opt_local.colorcolumn = '100'; vim.opt_local.textwidth = 100 end";
        }
        {
          event = [ "FileType" ];
          pattern = [ "python" ];
          group = "editor_width";
          callback.__raw = "function() vim.opt_local.colorcolumn = '88'; vim.opt_local.textwidth = 88 end";
        }
        {
          event = [ "LspAttach" ];
          group = "lsp_setup";
          callback.__raw = ''
            function(event)
              local client = vim.lsp.get_client_by_id(event.data.client_id)
              if client and client:supports_method("textDocument/inlayHint") then
                vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
              end
              local function map(mode, lhs, rhs, desc)
                vim.keymap.set(mode, lhs, rhs, { buffer = event.buf, desc = desc })
              end
              map("n", "K", vim.lsp.buf.hover, "LSP Hover")
              map("n", "gd", vim.lsp.buf.definition, "Goto Definition")
              map("n", "gD", vim.lsp.buf.declaration, "Goto Declaration")
              map("n", "gr", vim.lsp.buf.references, "List References")
              map("n", "gi", vim.lsp.buf.implementation, "Goto Implementation")
              map("n", "gt", vim.lsp.buf.type_definition, "Type Definition")
              map("n", "<leader>cr", vim.lsp.buf.rename, "Rename Symbol")
              map("i", "<C-k>", vim.lsp.buf.signature_help, "Signature Help")
            end
          '';
        }
      ];

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
          mode = [
            "n"
            "x"
            "o"
          ];
          key = "s";
          action.__raw = "function() require('flash').jump() end";
          options.desc = "Flash";
        }
        {
          mode = [
            "n"
            "x"
            "o"
          ];
          key = "S";
          action.__raw = "function() require('flash').treesitter() end";
          options.desc = "Flash Treesitter";
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

      userCommands = {
        LspInfo = {
          command.__raw = ''
            function()
              local clients = vim.lsp.get_clients({ bufnr = 0 })
              if #clients == 0 then return vim.notify("No LSP clients attached", vim.log.levels.WARN) end
              local lines = { "LSP clients attached to this buffer:", "" }
              for _, client in ipairs(clients) do
                table.insert(lines, ("  %s (id: %d)"):format(client.name, client.id))
                table.insert(lines, ("    root: %s"):format(client.root_dir or "none"))
                table.insert(lines, "")
              end
              vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
            end
          '';
          desc = "Show LSP info for current buffer";
        };
        LspLog = {
          command.__raw = "function() vim.cmd.edit(vim.lsp.get_log_path()) end";
          desc = "Open LSP log file";
        };
        LspRestart = {
          command.__raw = ''
            function()
              for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
                local name = client.name
                vim.lsp.stop_client(client.id)
                vim.defer_fn(function() vim.lsp.enable(name) end, 500)
              end
            end
          '';
          desc = "Restart LSP clients for current buffer";
        };
        Run = {
          nargs = "+";
          complete = "shellcmd";
          command.__raw = ''
            function(opts)
              local buffer = vim.api.nvim_create_buf(true, false)
              vim.api.nvim_buf_set_name(buffer, "Run Output")
              vim.cmd("botright split")
              vim.api.nvim_win_set_buf(0, buffer)
              vim.fn.jobstart(opts.args, {
                on_stdout = function(_, data) if data then vim.api.nvim_buf_set_lines(buffer, -1, -1, false, data) end end,
                on_stderr = function(_, data) if data then vim.api.nvim_buf_set_lines(buffer, -1, -1, false, data) end end,
              })
            end
          '';
        };
      };

      extraConfigLua = ''
        require("refjump").setup({ keymaps = { next = "]]", prev = "[[" } })
        require("lsp-file-operations").setup({})

        local ts_move = require("nvim-treesitter-textobjects.move")
        local ts_moves = {
          goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
          goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer", ["]A"] = "@parameter.inner" },
          goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer", ["[a"] = "@parameter.inner" },
          goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer", ["[A"] = "@parameter.inner" },
        }
        for method, mappings in pairs(ts_moves) do
          for key, query in pairs(mappings) do
            vim.keymap.set({ "n", "x", "o" }, key, function() ts_move[method](query, "textobjects") end,
              { silent = true, desc = ("TS %s (%s)"):format(method, query) })
          end
        end
        if vim.g.neovide then
          vim.opt.background = "dark"
          local paste = vim.fn.has("mac") == 1 and "<D-v>" or "<C-S-v>"
          vim.keymap.set("n", paste, '"+p', { desc = "Paste from system clipboard" })
          vim.keymap.set("v", paste, '"+p', { desc = "Paste from system clipboard" })
          vim.keymap.set("i", paste, "<C-r>+", { desc = "Paste from system clipboard" })
        end
        if vim.g.started_by_firenvim then vim.opt.guifont = "FiraCode Nerd Font:h14" end
      '';
    };

    home.shellAliases = {
      e = "nvim";
      r = "nvim -RM";
    };
  };
}
