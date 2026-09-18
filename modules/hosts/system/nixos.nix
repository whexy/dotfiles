{
  config,
  flake,
  lib,
  ...
}:
let
  cfg = config.dotfiles.system;
in
{
  config = lib.mkMerge [
    # Daily auto-upgrade of this host from the upstream repo.
    #
    # Wraps the built-in NixOS auto-upgrade (nixos-upgrade.service/.timer),
    # which runs the equivalent of:
    #   nixos-rebuild switch --refresh --flake <upstreamRef>#<configuration>
    (lib.mkIf cfg.autoUpgrade.enable {
      system.autoUpgrade = {
        enable = true;
        flake = "${flake.lib.upstreamRef}#${cfg.autoUpgrade.configuration}";
        dates = "04:00";
        randomizedDelaySec = "45min";
        # Catch up on missed runs (laptops asleep / machines off at 04:00).
        persistent = true;
      };
    })

    (lib.mkIf cfg.docs.enable { documentation.dev.enable = true; })

    (lib.mkIf cfg.fwupd.enable { services.fwupd.enable = true; })
  ];
}
