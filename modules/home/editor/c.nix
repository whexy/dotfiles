# C/C++: toolchains, build/debug tools, language server, and API man pages.
{
  config,
  pkgs,
  lib,
  perSystem,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.c.enable {
    home.packages =
      with pkgs;
      [
        clang
        cmake
        gdb
        gnumake
        llvm
        man-pages # Linux API man pages (sections 2-7)
        man-pages-posix # POSIX man pages (listen, socket, etc.)
      ]
      # GDB does not run on Apple silicon.
      ++ lib.optional stdenv.hostPlatform.isLinux perSystem.pwndbg.pwndbg;

    programs.nixvim = lib.mkIf config.dotfiles.editor.neovim.dev {
      plugins.treesitter.grammarPackages =
        with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [
          c
          cpp
          glsl
          ninja
        ];
      lsp.servers.clangd = {
        enable = true;
      };
    };
  };
}
