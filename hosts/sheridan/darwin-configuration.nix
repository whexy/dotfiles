{ flake, ... }:
{
  dotfiles = {
    system.autoUpgrade.enable = true;
    services.openssh.enable = true;
    # The T3 Code server publishes itself with `tailscale serve`.
    network.tailscale.userOperator = true;
  };

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
