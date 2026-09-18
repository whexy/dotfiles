# Streaming Darwin configuration: OBS via Homebrew cask (properly signed).
{ config, lib, ... }:
let
  cfg = config.dotfiles.streaming;
in
{
  config = lib.mkIf cfg.enable { homebrew.casks = [ "obs" ]; };
}
