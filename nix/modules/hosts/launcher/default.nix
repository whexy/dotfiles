# Launcher group: system support for the desktop launcher.
# Mirrors the home launcher group (which runs the daemon itself).
{ lib, ... }:
{
  options.dotfiles.launcher = {
    inputServer.enable = lib.mkEnableOption "the privileged Vicinae input server (Linux)";
  };
}
