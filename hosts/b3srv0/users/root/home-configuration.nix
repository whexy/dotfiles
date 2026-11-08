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
    autoUpgrade = {
      enable = true;
      # Off the tailnet, where CI announces commits; GitHub alone tells it.
      notify.enable = false;
    };
    tunnels.hostName = "b3srv0";
    t3code = {
      # Off the tailnet, so the tunnel is the server's only route.
      server = {
        enable = true;
      };
      pair.enable = true;
    };
  };

  home.homeDirectory = "/root";
}
