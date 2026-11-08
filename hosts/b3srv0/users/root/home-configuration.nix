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

  targets.genericLinux.enable = true;
  targets.genericLinux.gpu.enable = false;
  home.homeDirectory = "/root";
}
