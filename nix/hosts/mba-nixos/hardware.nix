# Desktop settings for VMware VM running on MacBook
{ ... }:

{
  imports = [
    ../../modules/nixos/platform-desktop-vm-vmware.nix
  ];

  # Uses VMware's "Use full resolution for Retina Display" + fullscreen,
  # so the guest sees a fixed Virtual-1 output at the host's native panel res.
  # scale = 2.0 matches macOS's backing scale factor, so cursor/widget/icon
  # sizes line up physically with the paired macOS host (mba). GTK text
  # parity is handled separately via hardware.display.macbookScreen below.
  hardware.monitors = [
    {
      connector = "Virtual-1";
      resolution = {
        width = 3420;
        height = 2146;
      };
      refreshRate = 60.000;
      scale = 2.0;
    }
  ];

  # We share a physical MacBook Retina panel with the macOS host. macOS uses a
  # 72-DPI baseline globally while GTK on Linux uses 96-DPI; without
  # compensation, GTK text (and Ghostty) renders 4/3 larger here than on macOS
  # at the same compositor scale. Enabling this flag lets the
  # macbook-screen-density home module apply text-scaling-factor = 0.75 so
  # text physically matches the macOS side.
  hardware.display.macbookScreen = true;
}
