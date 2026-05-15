# MacBook screen density compensation (Linux).
#
# When a NixOS host is running on a MacBook Retina panel — typically a VM on
# top of macOS with "Use full resolution for Retina Display" enabled — we
# want UI sizes (cursor, widgets, icons) AND text to physically match the
# paired macOS host on the same screen.
#
# Setting niri's compositor scale to match macOS's backing factor (2.0×) gets
# us cursor/widget/icon parity for free. Text is a separate problem:
#
#   Ghostty's source (`src/font/face.zig`) bakes in:
#     default_dpi = 72  on macOS
#     default_dpi = 96  on Linux
#
#   physical_em_px = font_size × content_scale × default_dpi / 72
#
# GTK/Pango as a whole follows the same 96-DPI baseline convention on Linux,
# so every GTK app — not just Ghostty — renders text 4/3 larger than its
# macOS counterpart at the same compositor scale.
#
# Setting GNOME's text-scaling-factor to 0.75 (= 72/96) makes GTK pretend the
# system is at a 72-DPI baseline, exactly mirroring macOS. Combined with a
# compositor scale of 2.0×:
#
#   GTK effective DPI  = 96 × 0.75 × 2.0 = 144  (== macOS 72 × 2.0)
#   Ghostty 14pt em px = 14 × (2.0 × 0.75) × 96 / 72 = 28  (== macOS 14 × 2.0)
#
# Widget/cursor/icon sizing is not affected by text-scaling-factor, so it
# continues to follow the compositor scale and stays at macOS density.
#
# Gated on `hardware.display.macbookScreen` so that standalone Linux machines
# with normal monitors (e.g. ord) keep their default GTK DPI and are not
# regressed.
{
  lib,
  osConfig,
  ...
}:
{
  dconf.settings = lib.mkIf (osConfig.hardware.display.macbookScreen or false) {
    "org/gnome/desktop/interface" = {
      text-scaling-factor = 0.75;
    };
  };
}
