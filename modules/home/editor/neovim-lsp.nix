# Nixvim module (not a Home Manager module) with the development profile's
# language tooling: LSP, completion, formatting, linting and diagnostics.
# Language modules enable the servers and tools themselves.
{ pkgs, ... }:
{
  plugins = {
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

  autoGroups.lsp_setup.clear = true;
  autoCmd = [
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
  };

  extraConfigLua = ''
    require("refjump").setup({ keymaps = { next = "]]", prev = "[[" } })
    require("lsp-file-operations").setup({})
  '';
}
