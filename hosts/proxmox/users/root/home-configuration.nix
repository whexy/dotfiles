{ inputs, ... }:
{
  imports = [
    inputs.self.homeModules.standalone
  ]
  ++ inputs.self.lib.homeCapsModules [
    "base"
    "sysadmin"
  ];

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
    # The Macs reach root's personal Rex server over ssh on the tailnet.
    terminal.rex.route = "ssh://root@${inputs.self.lib.tailnetHost "proxmox"}";
  };

  home.homeDirectory = "/root";

  home.stateVersion = "26.05";
}
