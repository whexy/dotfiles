# NixOS option: hardware.display
# Declares display-related characteristics that home modules may need to know
# about. Hardware configs set these; home modules consume them via osConfig.
{ lib, ... }:
{
  options.hardware.display = {
    macbookScreen = lib.mkEnableOption ''
      this machine is running on a MacBook Retina panel (typically a NixOS VM
      hosted on macOS via VMware/UTM with "Use full resolution for Retina
      Display" enabled).

      macOS renders the entire UI against a 72-DPI baseline scaled by the
      backing factor (e.g. 2.0× on Retina). GTK on Linux uses a 96-DPI
      baseline instead, so at the same compositor scale every GTK app —
      including Ghostty — renders text 4/3 larger than its macOS counterpart
      on the same physical panel.

      When this option is enabled, home modules apply a GTK
      text-scaling-factor of 0.75 (= 72/96) so that GTK text physically
      matches macOS rendering at the same compositor scale. Cursor, widget
      and icon sizes are unaffected since they continue to follow the
      compositor scale directly.

      Only enable this on machines that share a physical MacBook panel with a
      paired macOS host; on standalone Linux hardware the default GTK DPI
      baseline is correct and this option should remain off.
    '';
  };
}
