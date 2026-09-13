# Firefox as an automation target (headless browser control for agents),
# independent of the profile-managed desktop browser in firefox.nix.
#
# Automation never touches the user's real profile: firefox-devtools-mcp runs
# Firefox under its own dedicated profile, so only the binary is needed here.
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
  cfg = config.dotfiles.browser.firefox;
in
{
  config = lib.mkIf cfg.automation.enable {
    dotfiles.browser.firefox.automation.binaryPath = lib.mkDefault (
      if isDarwin then
        # nixpkgs has no cached Firefox for aarch64-darwin (both firefox and
        # firefox-bin would build from source), so macOS uses the Homebrew cask
        # that the system browser group installs.
        "/Applications/Firefox.app/Contents/MacOS/firefox"
      else if cfg.enable then
        # Reuse the profile-managed wrapper rather than adding a second
        # Firefox to the closure.
        "${config.programs.firefox.finalPackage}/bin/firefox"
      else
        "${pkgs.firefox}/bin/firefox"
    );

    # When the desktop browser is enabled, programs.firefox already puts
    # Firefox on PATH; installing it twice would collide on bin/firefox.
    home.packages = lib.optional (!isDarwin && !cfg.enable) pkgs.firefox;
  };
}
