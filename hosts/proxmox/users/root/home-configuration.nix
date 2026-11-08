{ inputs, ... }:
{
  imports = [
    inputs.self.homeModules.all
  ]
  ++ inputs.self.lib.homeCapsModules [
    "base"
    "sysadmin"
  ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = inputs.self.lib.commonOverlays;
  dotfiles = {
    autoUpgrade.enable = true;
    # proxmox is on the tailnet, and root is trusted by its Nix daemon.
    nix.ciCache.enable = true;
    tunnels.hostName = "proxmox";
    t3code = {
      server = {
        enable = true;
        tailnet.enable = true;
      };
      pair.enable = true;
    };
  };

  targets.genericLinux.enable = true;
  targets.genericLinux.gpu.enable = false;
  home.homeDirectory = "/root";
}
