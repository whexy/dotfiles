# Browser group: desktop browsers.
#
# Integrated homes follow the system browser group, which installs Firefox
# as a Homebrew cask on macOS; standalone homes set the switches.
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.browser.firefox;
  systemFirefox =
    if osConfig != null then
      osConfig.dotfiles.browser.firefox
    else
      {
        enable = false;
        automation.enable = false;
      };
  fromSystem =
    value: path: description:
    lib.mkOption {
      type = lib.types.bool;
      default = value;
      defaultText = lib.literalExpression "osConfig.dotfiles.browser.firefox.${path}, or false without osConfig";
      description = "Whether to enable ${description}.";
    };
in
{
  options.dotfiles.browser = {
    firefox = {
      enable = fromSystem systemFirefox.enable "enable" "Firefox";

      automation = {
        enable =
          fromSystem systemFirefox.automation.enable "automation.enable"
            "Firefox as a headless automation target for agents";
        mcp.enable = lib.mkEnableOption "Mozilla's Firefox DevTools MCP server for every agent, driving this browser";

        binaryPath = lib.mkOption {
          type = lib.types.str;
          description = ''
            Firefox executable driven by automation tooling. Defaults to the
            profile-managed Firefox on Linux and to the Homebrew cask on macOS.
          '';
        };
      };
    };
  };

  imports = [
    ./automation.nix
    ./firefox-devtools-mcp.nix
    ./firefox.nix
  ];

  config.assertions =
    lib.optional
      (osConfig != null && pkgs.stdenv.hostPlatform.isDarwin && (cfg.enable || cfg.automation.enable))
      {
        assertion = systemFirefox.enable || systemFirefox.automation.enable;
        message = "On macOS, Firefox is the Homebrew cask the system browser group installs; enable it with the system's dotfiles.browser.firefox options.";
      };
}
