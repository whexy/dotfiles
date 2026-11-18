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
    hardware.gpu.vendor = "nvidia";
    tunnels.hostName = "venus";
    # Off the tailnet, so the tunnel is the server's only route.
    t3code.server.enable = true;
    # A shared server, kept off the tailnet; its agents reach the tailnet
    # gateways through this user's own relay, and ssh reaches it through the
    # relay too.
    tailnetRelay = {
      enable = true;
      hostName = "venus-relay";
      serves.ssh = {
        port = 22;
        target = "127.0.0.1:22";
      };
    };
    terminal.rex.server = {
      enable = true;
      hostName = "venus-rex";
    };
  };

  home.stateVersion = "26.05";
}
