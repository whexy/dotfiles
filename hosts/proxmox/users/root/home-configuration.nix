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
  nixpkgs.overlays = [
    inputs.self.lib.overlays.unstable
    inputs.self.lib.overlays.llm-tools
  ];
  dotfiles = {
    autoUpgrade.enable = true;
    # proxmox is on the tailnet, and root is trusted by its Nix daemon.
    nix.ciCache.enable = true;
    agents.t3code = {
      server = {
        enable = true;
        tailnet.enable = true;
        tunnel.hostName = "proxmox";
      };
      pair.enable = true;
    };
  };

  targets.genericLinux.enable = true;
  targets.genericLinux.gpu.enable = false;
  home.homeDirectory = "/root";
}
