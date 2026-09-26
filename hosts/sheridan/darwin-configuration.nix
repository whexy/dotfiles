{ flake, ... }:
{
  dotfiles.system.autoUpgrade.enable = true;
  # The T3 Code server publishes itself with `tailscale serve`.
  dotfiles.network.tailscale.userOperator = true;

  imports = flake.lib.darwinHost {
    system = "aarch64-darwin";
    hostName = "sheridan";
    caps = [
      "base"
      "dev-lite"
      "gui"
    ];
    modules = [ ./hardware.nix ];
  };
}
