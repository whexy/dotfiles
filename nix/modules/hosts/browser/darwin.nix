# Browser Darwin configuration: Firefox via Homebrew cask (properly signed
# for 1Password integration; the home module only manages the profile).
{ config, lib, ... }:
let
  cfg = config.dotfiles.browser;
in
{
  config = lib.mkIf cfg.firefox.enable { homebrew.casks = [ "firefox" ]; };
}
