# unkernel guest platform: a Linux kernel compiled to WebAssembly, which runs
# this host's aarch64 user space in a browser tab or under Node.
{ lib, ... }:
{
  options.dotfiles.platform.unkernel = {
    enable = lib.mkEnableOption "the unkernel guest platform, whose base system mounts this host's image under an overlay root and runs its init";
    display = {
      enable = lib.mkEnableOption "the display the unkernel host offers: a virtio-gpu KMS device and evdev input, with udev, Mesa and a seat for a Wayland compositor";
      width = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1280;
        description = "Width in pixels of the display's only mode.";
      };
      height = lib.mkOption {
        type = lib.types.ints.positive;
        default = 800;
        description = "Height in pixels of the display's only mode.";
      };
      session = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "niri-session";
        description = ''
          Command the host's user runs at boot from a login shell, as a
          Wayland session on seat0, or null to start none.
        '';
      };
    };
    launcherSystem = lib.mkOption {
      type = lib.types.str;
      default = "x86_64-linux";
      description = ''
        System of the machine that builds this host's image and serves or
        boots it (`system.build.unkernel`), which need not be the host's own.
      '';
    };
  };
}
