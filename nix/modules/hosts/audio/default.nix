# Audio group: sound server stack.
{ lib, ... }:
{
  options.dotfiles.audio = {
    enable = lib.mkEnableOption "PipeWire audio stack (Linux)";
  };
}
