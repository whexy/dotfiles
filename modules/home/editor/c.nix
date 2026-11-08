# C/C++: toolchains, build/debug tools, language server, and API man pages.
{
  config,
  pkgs,
  lib,
  perSystem,
  ...
}:
{
  config = import ./language.nix { inherit config lib; } "c" {
    packages =
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
    grammars = [
      "c"
      "cpp"
      "glsl"
      "ninja"
    ];
    nixvim.lsp.servers.clangd = {
      enable = true;
    };
  };
}
