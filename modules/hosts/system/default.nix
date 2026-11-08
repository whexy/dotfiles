# System group: timezone, auto-upgrade, boot menu size, developer
# documentation, Xcode management.
{ config, lib, ... }:
let
  cfg = config.dotfiles.system;
in
{
  options.dotfiles.system = {
    timezone.enable = lib.mkEnableOption "the dotfiles timezone (America/Chicago)";

    autoUpgrade = import ../../../packages/dotfiles-upgraded/options.nix {
      inherit lib;
      subject = "host";

      configuration = lib.mkOption {
        type = lib.types.str;
        default = config.dotfiles.host.hostName;
        defaultText = "config.dotfiles.host.hostName";
        description = ''
          The nixosConfigurations.<name> (NixOS) or
          darwinConfigurations.<name> (Darwin) output of the upstream repo
          (flake.lib.upstreamRef) to switch to. Override when the flake
          output name differs from the runtime hostname.
        '';
        example = "remote-dev";
      };

      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/dotfiles-upgraded";
        readOnly = true;
        description = ''
          Where the daemon keeps its state and publishes its health signal,
          status.json. Fixed because NixOS's StateDirectory= creates it.
        '';
      };
    };

    fwupd.enable = lib.mkEnableOption "Linux Vendor firmware service";

    docs.enable = lib.mkEnableOption "developer documentation (man pages for syscalls & libc, sections 2 and 3)";

    xcodes.enable = lib.mkEnableOption "the Xcodes app for installing and switching Xcode versions (macOS)";
  };

  config = lib.mkIf cfg.timezone.enable { time.timeZone = "America/Chicago"; };
}
