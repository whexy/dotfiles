# dev home cap preset: full development environment; dev-lite plus every
# language toolchain and the heavy tooling bundles.
# Package bundles live in the `tooling` and `editor` feature groups; this
# preset enables all of them. Hosts disable bundles with plain assignments.
{ lib, pkgs, ... }:
{
  imports = [ ./dev-lite.nix ];

  home.packages = [ pkgs.sd ];

  dotfiles = {
    agenticTooling = {
      video.studio.enable = lib.mkDefault true;
      formalVerification.enable = lib.mkDefault true;
    };
    # Agents drive Firefox headlessly, so a dev machine needs the browser
    # whether or not it has a display.
    browser.firefox.automation = {
      enable = lib.mkDefault true;
      mcp.enable = lib.mkDefault true;
    };
    terminal.adopt.enable = lib.mkDefault true;
    editor = {
      # Neovim commit dc89344 added a third `optional` element to `--api-info`
      # parameters, which neovide 0.16.2 refuses to parse, so the GUI cannot
      # start at all on nightly. Re-enable once a neovide release carries
      # neovide#3530.
      neovim.nightly = lib.mkDefault false;
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
