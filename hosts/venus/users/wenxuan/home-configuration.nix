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
    inputs.self.lib.overlays.llm-tools
  ];
  dotfiles = {
    autoUpgrade.enable = true;
    # No T3 server runs here, and the fork's t3 comes only from
    # whexy-t3code.cachix.org, which this home's Nix daemon may not trust;
    # without it every upgrade would compile T3 from source.
    t3code.enable = false;
  };

  targets.genericLinux.enable = true;
  targets.genericLinux.gpu.enable = false;
}
