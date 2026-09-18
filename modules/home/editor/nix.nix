# Nix: language server and formatter.
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.nix.enable {
    programs.nixvim = lib.mkIf config.dotfiles.editor.neovim.dev {
      plugins.treesitter.grammarPackages =
        with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [ nix ];
      lsp.servers.nixd = {
        enable = true;
      };
      plugins.conform-nvim.settings.formatters_by_ft.nix = [ "nixfmt" ];
    };
  };
}
