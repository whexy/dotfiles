# Zig: toolchain and language server.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = import ./language.nix { inherit config lib; } "zig" {
    packages = with pkgs; [
      zig
    ];
    grammars = [ "zig" ];
    nixvim.lsp.servers.zls = {
      enable = true;
    };
  };
}
