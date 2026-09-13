# Browser group: Firefox.
{ lib, ... }:
{
  options.dotfiles.browser = {
    firefox = {
      enable = lib.mkEnableOption "Firefox";

      automation = {
        enable = lib.mkEnableOption "Firefox as a headless automation target for agents";

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
    ./firefox.nix
  ];
}
