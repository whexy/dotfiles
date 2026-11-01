{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.nix;
  cleanup = pkgs.callPackage ../../../packages/nix-cleanup { nixPackage = config.nix.package; };
in
{
  config = lib.mkIf cfg.gc.enable {
    systemd.services.nix-gc.script = lib.mkForce "exec ${lib.getExe cleanup} --system";
    nix.gc = {
      dates = "daily";
      randomizedDelaySec = "2h";
    };
  };
}
