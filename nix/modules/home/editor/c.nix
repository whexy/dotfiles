# C/C++: toolchains, build/debug tools, language server, and API man pages.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.c.enable {
    home.packages = with pkgs; [
      clang
      clang-tools
      cmake
      gdb
      gnumake
      llvm
      man-pages # Linux API man pages (sections 2-7)
      man-pages-posix # POSIX man pages (listen, socket, etc.)
    ];
  };
}
