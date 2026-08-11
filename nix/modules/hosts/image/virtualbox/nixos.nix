{
  config,
  flake,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.image.virtualbox;
  username = config.dotfiles.host.username;
in
{
  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ flake.lib.overlays.lkl-bigmem ];
    system.stateVersion = "25.11";

    image.modules.virtualbox = {
      virtualbox.memorySize = 16 * 1024;
      virtualisation = {
        diskSize = 50 * 1024;
        virtualbox.guest = {
          enable = true;
          clipboard = true;
          seamless = true;
          dragAndDrop = true;
        };
      };
    };

    virtualisation.virtualbox.guest = {
      enable = true;
      clipboard = true;
    };
    hardware.graphics.enable = true;

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
          user = "greeter";
        };
        initial_session = {
          command = "niri-session";
          user = username;
        };
      };
    };

    boot.loader.grub.device = lib.mkDefault "/dev/sda";
    fileSystems."/" = lib.mkDefault {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
  };
}
