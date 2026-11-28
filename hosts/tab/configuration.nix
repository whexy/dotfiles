{
  config,
  flake,
  hostName,
  pkgs,
  ...
}:
{
  # No cap: a tab downloads what its image holds, so this host names the few
  # features it has.
  imports = flake.lib.nixosHost {
    system = "aarch64-linux";
    inherit hostName;
    caps = [ ];
  };

  # A toy: this host runs in a browser tab, on unkernel (`just tab`).
  dotfiles = {
    platform.unkernel = {
      enable = true;
      display = {
        enable = true;
        session = "niri-session";
      };
    };
    # niri scales an output it has no declaration for by 1.5.
    hardware.monitors = [
      {
        connector = "Virtual-1";
        resolution = { inherit (config.dotfiles.platform.unkernel.display) width height; };
        scale = 1.0;
      }
    ];
    nix = {
      caches.enable = true;
      # The CI cache is on the tailnet, which the tab joins only after a
      # login, and Nix waits on a substituter it cannot reach.
      ciCache.enable = false;
    };
    network.tailscale = {
      enable = true;
      userOperator = true;
    };
    # The user has no password to give sudo.
    security.passwordlessSudo.enable = true;
  };

  # A reload boots the image again, so nothing here rebuilds or installs
  # the system.
  system.disableInstallerTools = true;
  documentation = {
    enable = false;
    man.enable = false;
  };
  environment.defaultPackages = [ ];
  # The registry's nixpkgs would be a third of the image; `nix run nixpkgs#...`
  # fetches the unstable branch instead.
  nixpkgs.flake = {
    setFlakeRegistry = false;
    setNixPath = false;
  };

  # Ghostty's font alone, without the CJK fonts of dotfiles.fonts.
  fonts = {
    packages = [ pkgs.nerd-fonts.fira-code ];
    fontconfig.defaultFonts.monospace = [ "FiraCode Nerd Font" ];
  };

  # Home Manager's xdg.portal, which the niri home module enables, asserts
  # these.
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  system.stateVersion = "26.05";
}
