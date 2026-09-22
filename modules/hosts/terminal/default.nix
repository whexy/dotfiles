{ lib, ... }:
{
  options.dotfiles.terminal.cmux.enable = lib.mkEnableOption "the cmux terminal app (macOS)";
}
