{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.compat;
  wsl = config.dotfiles.host.wsl;

  host = pkgs.stdenv.hostPlatform.system;
  universe = [
    "x86_64-linux"
    "aarch64-linux"
    "riscv64-linux"
  ];
  emulated = lib.remove host universe;
in
{
  config = lib.mkMerge [
    # Disable envfs for WSL, because Windows expects /bin/mount to exist.
    (lib.mkIf cfg.envfs.enable { services.envfs.enable = lib.mkIf (!wsl) true; })

    (lib.mkIf cfg.nix-ld.enable { programs.nix-ld.enable = true; })

    # Emulate other platforms
    (lib.mkIf cfg.binfmt.enable { boot.binfmt.emulatedSystems = emulated; })
  ];
}
