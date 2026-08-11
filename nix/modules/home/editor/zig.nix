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
      zls
    ];
  };
}
