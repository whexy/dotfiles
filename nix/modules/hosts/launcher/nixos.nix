# Vicinae input server: the helper that reads /dev/input/event* and writes to
# /dev/uinput, so that "paste to focused window" and snippet expansion work.
#
# The helper gets cap_dac_override through a wrapper instead of putting the
# user in the `input` group: group membership would let every process of that
# user read all keyboard events, while the capability stays with this one
# binary. The home module points the daemon at the wrapper with
# VICINAE_INPUT_SERVER_BIN; both sides take vicinae from the same `pkgs`, so
# the helper always speaks the daemon's protocol version.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.launcher;
in
{
  config = lib.mkIf cfg.inputServer.enable {
    hardware.uinput.enable = true;

    security.wrappers.vicinae-input-server = {
      source = "${pkgs.vicinae}/libexec/vicinae/vicinae-input-server";
      capabilities = "cap_dac_override+ep";
      owner = "root";
      group = "root";
    };
  };
}
