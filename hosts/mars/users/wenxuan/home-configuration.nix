{ inputs, ... }:
{
  imports = [
    inputs.self.homeModules.all
  ]
  ++ inputs.self.lib.homeCapsModules [
    "base"
    "dev"
  ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.self.lib.overlays.unstable
    inputs.self.lib.overlays.firefox-devtools-mcp-profile
    inputs.self.lib.overlays.llm-tools
  ];
  dotfiles = {
    autoUpgrade.enable = true;
    # Off the tailnet, so T3 Code clients connect over the LAN.
    agents.t3code.server = {
      enable = true;
      network = "lan";
    };
  };

  targets.genericLinux.enable = true;
  targets.genericLinux.gpu.enable = false;
  home.homeDirectory = "/data/wenxuan";
}
