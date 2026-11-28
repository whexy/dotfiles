# unkernel guest platform: a Linux kernel compiled to WebAssembly, which runs
# this host's aarch64 user space in a browser tab or under Node.
{ lib, ... }:
{
  options.dotfiles.platform.unkernel = {
    enable = lib.mkEnableOption "the unkernel guest platform, whose base system mounts this host's image under an overlay root and runs its init";
    wayland.enable = lib.mkEnableOption "running Wayland applications as browser tabs through the wland relay";
    apps = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            command = lib.mkOption { type = lib.types.listOf lib.types.str; };
            wayland = lib.mkEnableOption "launching the application as a Wayland window";
          };
        }
      );
      default = [ ];
      description = "Applications offered by the browser launcher.";
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
