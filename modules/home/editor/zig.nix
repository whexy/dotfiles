# Zig: toolchain and language server.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.zig.enable {
    home.packages = with pkgs; [
      zig
    ];

    programs.nixvim = lib.mkIf config.dotfiles.editor.neovim.dev {
      plugins.treesitter.grammarPackages =
        with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [ zig ];
      lsp.servers.zls = {
        enable = true;
      };
    };
  };
}
