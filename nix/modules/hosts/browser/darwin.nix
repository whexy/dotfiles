# Browser Darwin configuration: Firefox via Homebrew cask (properly signed
# for 1Password integration; the home module only manages the profile).
#
# The cask also serves headless automation, because nixpkgs has no cached
# Firefox build for aarch64-darwin.
{ config, lib, ... }:
let
  cfg = config.dotfiles.browser.firefox;
in
{
  config = lib.mkIf (cfg.enable || cfg.automation.enable) { homebrew.casks = [ "firefox" ]; };
}
