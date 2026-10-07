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

  config = lib.optionalAttrs (options ? programs.chromium) {
    programs.chromium = lib.mkIf config.dotfiles.browser.chromium.enable {
      enable = true;
      extraOpts = chromiumPolicies;
    };
  };
}
