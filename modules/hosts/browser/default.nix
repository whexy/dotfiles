# Browser group: system integration for browsers managed by Home Manager.
{ lib, ... }:
{
  options.dotfiles.browser.firefox = {
    enable = lib.mkEnableOption "Firefox";
    automation.enable = lib.mkEnableOption "Firefox as a headless automation target for agents";
  };
}
