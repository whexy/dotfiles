# Typst: compiler, language server, and formatter.
{
  config,
  pkgs,
  lib,
  ...
}:
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
          settings.dependencies_bin.tinymist = "tinymist";
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
