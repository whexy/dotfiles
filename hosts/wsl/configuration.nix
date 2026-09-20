{ flake, lib, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "wsl";
    wsl = true;
    caps = [
      "base"
      "dev"
    ];
    modules = [
      ./hardware.nix
      ./nvidia.nix
    ];
    overlays = [
      flake.lib.overlays.op-wsl
      flake.lib.overlays.ssh-wsl
      flake.lib.overlays.tailscale-wsl
    ];
  };

  dotfiles = {
    system.autoUpgrade.enable = true;
    # WSL shares the Windows network stack, so the Tailscale node belongs to
    # the Windows client; a Linux tailscaled here would be a second node.
    network.tailscale.enable = lib.mkForce false;
  };
}
