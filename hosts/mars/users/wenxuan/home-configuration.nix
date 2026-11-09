{ inputs, ... }:
{
  imports = [
    inputs.self.homeModules.standalone
  ]
  ++ inputs.self.lib.homeCapsModules [
    "base"
    "dev"
  ];

  dotfiles = {
    autoUpgrade.enable = true;
    tunnels.hostName = "mars";
    # Off the tailnet, so the tunnel is the server's only route.
    t3code.server.enable = true;
    # A shared server, kept off the tailnet; its agents reach the tailnet
    # gateways through this user's own relay.
    tailnetRelay = {
      enable = true;
      hostName = "mars-relay";
    };
  };

  home.homeDirectory = "/data/wenxuan";

  home.stateVersion = "26.05";
}
