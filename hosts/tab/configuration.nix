{
  flake,
  hostName,
  lib,
  pkgs,
  ...
}:
let
  waylandRun = pkgs.writeShellApplication {
    name = "wayland-run";
    text = ''
      export XDG_RUNTIME_DIR=/run/tabos-wayland
      export WAYLAND_DISPLAY=wayland-0
      export GDK_BACKEND=wayland
      if [[ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]]; then
        echo "TabOS Wayland is unavailable. Open the guest in a browser and wait for it to start." >&2
        exit 1
      fi
      exec "$@"
    '';
  };
in
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
      wayland.enable = true;
      apps = [
        {
          name = "Calculator";
          command = [
            "${lib.getExe waylandRun}"
            "${lib.getExe pkgs.galculator}"
          ];
          wayland = true;
        }
        {
          name = "Neovim";
          command = [ "nvim" ];
        }
        {
          name = "tmux";
          command = [ "tmux" ];
        }
        {
          name = "Claude Code";
          command = [ "claude" ];
        }
      ];
    };
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
  # The registry's nixpkgs would be a third of the image; `nix run nixpkgs#...`
  # fetches the unstable branch instead.
  nixpkgs.flake = {
    setFlakeRegistry = false;
    setNixPath = false;
  };

  fonts.packages = [ pkgs.dejavu_fonts ];
  environment = {
    defaultPackages = [ ];
    systemPackages = [
      waylandRun
      pkgs.galculator
    ];
  };

  system.stateVersion = "26.05";
}
