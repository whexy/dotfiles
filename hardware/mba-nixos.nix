# Desktop settings for VMware VM running on MacBook
{ ... }:

{
  imports = [
    ./vm-desktop-vmware.nix
  ];

  # Uses VMware's "Use full resolution for Retina Display" + fullscreen,
  # so the guest sees a fixed Virtual-1 output at the host's native panel res.
  # scale = 1.5 matches macOS's default logical density and gives pixel-perfect integer scaling.
  hardware.monitors = [
    {
      connector = "Virtual-1";
      resolution = {
        width = 3420;
        height = 2146;
      };
      refreshRate = 60.000;
      scale = 1.5;
    }
  ];

}
