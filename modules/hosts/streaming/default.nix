# Streaming group: OBS Studio system integration.
# Pairs with the home streaming group (streaming tools).
{ lib, ... }:
{
  options.dotfiles.streaming = {
    enable = lib.mkEnableOption "OBS Studio (Linux: virtual camera; macOS: Homebrew cask)";
  };
}
