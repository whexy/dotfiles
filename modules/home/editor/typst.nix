# Typst: compiler, language server, and formatter.
args@{
  config,
  pkgs,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  isWsl = osConfig != null && osConfig.dotfiles.host.wsl;
  # No screen to open a browser on. WSL has no desktop of its own but opens
  # previews in Windows.
  isHeadless =
    osConfig != null
    && (osConfig.dotfiles.hardware.headless || !(osConfig.dotfiles.desktop.enable || isWsl));
in
{
  config = lib.mkIf config.dotfiles.editor.typst.enable {
    home.packages = with pkgs; [
      typst
    ];

    programs.nixvim = lib.mkIf config.dotfiles.editor.neovim.dev {
      plugins.treesitter.grammarPackages =
        with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [ typst ];
      lsp.servers.tinymist = {
        enable = true;
        config.settings.formatterMode = "typstyle";
      };
      plugins = {
        typst-preview = {
          enable = true;
          settings = {
            dependencies_bin.tinymist = "tinymist";
            # The plugin opens previews with wslview on WSL, which nixpkgs no
            # longer ships.
            open_cmd = lib.mkIf isWsl "explorer.exe %s";
          };
          # Serve the preview on the tailnet and report its URL for a browser
          # on another machine. The address is looked up once a Typst buffer
          # opens rather than on every Neovim startup.
          luaConfig.post = lib.mkIf isHeadless ''
            require("typst-preview.utils").visit = function(link)
              vim.notify("Typst preview: http://" .. link)
            end
            vim.api.nvim_create_autocmd("FileType", {
              pattern = "typst",
              once = true,
              callback = function()
                if vim.fn.executable("tailscale") == 0 then return end
                local out = vim.system({ "tailscale", "ip", "-4" }, { text = true }):wait()
                if out.code == 0 then
                  require("typst-preview.config").opts.host = vim.trim(out.stdout)
                end
              end,
            })
          '';
        };
        conform-nvim.settings = {
          formatters_by_ft.typst = [ "typstyle" ];
          formatters.typstyle.append_args = [ "--wrap-text" ];
        };
      };
      userCommands.TypstPin.command.__raw = ''
        function()
          local client = vim.lsp.get_clients({ name = "tinymist" })[1]
          if not client then return vim.notify("tinymist not running!", vim.log.levels.ERROR) end
          client.request("workspace/executeCommand", {
            command = "tinymist.pinMain",
            arguments = { vim.api.nvim_buf_get_name(0) },
          }, function(err)
            vim.notify(err and ("error pinning: " .. err) or "successfully pinned",
              err and vim.log.levels.ERROR or vim.log.levels.INFO)
          end)
        end
      '';
    };
  };
}
