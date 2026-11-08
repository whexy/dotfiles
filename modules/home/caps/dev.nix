# dev home cap preset: full development environment; dev-lite plus every
# language toolchain and the heavy tooling bundles.
# Package bundles live in the `tooling` and `editor` feature groups; this
# preset enables all of them. Hosts disable bundles with plain assignments.
args@{ lib, ... }:
let
  osConfig = args.osConfig or null;
in
{
  imports = [ ./dev-lite.nix ];

  dotfiles = {
    agenticTooling = {
      video.studio.enable = lib.mkDefault true;
      formalVerification.enable = lib.mkDefault true;
    };
    # Agents drive Firefox headlessly, so a dev machine needs the browser
    # whether or not it has a display.
    browser.firefox.automation = {
      # Integrated homes follow the system dev cap.
      enable = lib.mkIf (osConfig == null) (lib.mkDefault true);
      mcp.enable = lib.mkDefault true;
    };
    terminal.adopt.enable = lib.mkDefault true;
    editor = {
      c.enable = lib.mkDefault true;
      go.enable = lib.mkDefault true;
      javascript.enable = lib.mkDefault true;
      lua.enable = lib.mkDefault true;
      rust.enable = lib.mkDefault true;
      zig.enable = lib.mkDefault true;
    };

    tooling = {
      extras.enable = lib.mkDefault true;
      debug.enable = lib.mkDefault true;
      woodpecker.enable = lib.mkDefault true;
    };
  };
}
