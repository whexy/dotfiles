# Browser group: system integration for browsers managed by Home Manager.
{
  config,
  lib,
  options,
  ...
}:
let
  chromiumPolicies = import ../../home/browser/chromium/shared.nix;
in
{
  options.dotfiles.browser = {
    firefox = {
      enable = lib.mkEnableOption "Firefox";
      automation.enable = lib.mkEnableOption "Firefox as a headless automation target for agents";
    };
    chromium.enable = lib.mkEnableOption "Chromium-based browser policies";
  };

  config = lib.mkIf (options ? programs.chromium && config.dotfiles.browser.chromium.enable) {
    programs.chromium = {
      enable = true;
      extraOpts = chromiumPolicies;
    };
  };
}
