# Streaming group: OBS Studio system integration.
# The home streaming group adds its tools wherever this is on.
{ lib, ... }:
{
  options.dotfiles.streaming = {
    enable = lib.mkEnableOption "OBS Studio (Linux: virtual camera; macOS: Homebrew cask)";
  };
}
