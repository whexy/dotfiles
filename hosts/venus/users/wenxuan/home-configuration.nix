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
    # No T3 server runs here, and the fork's t3 comes only from
    # whexy-t3code.cachix.org, which this home's Nix daemon may not trust;
    # without it every upgrade would compile T3 from source.
    t3code.enable = false;
    # A shared server, kept off the tailnet; its agents reach the tailnet
    # gateways through this user's own relay.
    tailnetRelay = {
      enable = true;
      hostName = "venus-relay";
    };
  };

  home.stateVersion = "26.05";
}
