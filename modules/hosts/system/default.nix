# System group: timezone, auto-upgrade, developer documentation.
{ config, lib, ... }:
let
  cfg = config.dotfiles.system;
in
{
  options.dotfiles.system = {
    timezone.enable = lib.mkEnableOption "the dotfiles timezone (America/Chicago)";

    autoUpgrade = {
      enable = lib.mkEnableOption "the dotfiles-upgraded daemon, which switches this host to each upstream commit that passes CI";

      configuration = lib.mkOption {
        type = lib.types.str;
        default = config.dotfiles.host.hostName;
        defaultText = "config.dotfiles.host.hostName";
        description = ''
          The nixosConfigurations.<name> (NixOS) or
          darwinConfigurations.<name> (Darwin) output of the upstream repo
          (flake.lib.upstreamRef) to switch to. Override when the flake
          output name differs from the runtime hostname (e.g. moore has
          networking.hostName "moore-vm").
        '';
        example = "remote-dev";
      };

      pollInterval = lib.mkOption {
        type = lib.types.str;
        default = "10m";
        description = ''
          Base interval between upstream ref checks, as a Go duration. The
          daemon jitters each tick so the fleet does not poll in lockstep,
          and raises the floor when GitHub asks it to.
        '';
        example = "30m";
      };

      maxAttempts = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = ''
          Switch attempts, with exponential backoff, before the daemon gives
          up on a commit and waits for a newer one. A transient fault and a
          genuinely broken commit are indistinguishable by exit code, so
          retrying lets transients heal without blocking later commits.
        '';
      };

      requireCiPass = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Only switch to commits whose GitHub commit status is success.
          Disabling this removes the only gate on what reaches this host.
        '';
      };
    };

    fwupd.enable = lib.mkEnableOption "Linux Vendor firmware service";

    docs.enable = lib.mkEnableOption "developer documentation (man pages for syscalls & libc, sections 2 and 3)";
  };

  config = lib.mkIf cfg.timezone.enable { time.timeZone = "America/Chicago"; };
}
