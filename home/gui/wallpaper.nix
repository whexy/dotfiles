# Desktop wallpaper (cross-platform)
{
  lib,
  pkgs,
  darwin ? false,
  ...
}:
{
  # Linux: swaybg paints the wallpaper; spawned by niri at startup.
  home.packages = lib.optionals (!darwin) [ pkgs.swaybg ];

  programs = lib.optionalAttrs (!darwin) {
    niri.settings.spawn-at-startup = [
      {
        command = [
          "swaybg"
          "--image"
          "${./wallpaper.jpg}"
          "--mode"
          "fill"
        ];
      }
    ];
  };

  # macOS: tell Finder to set the desktop picture on each activation.
  home.activation = lib.optionalAttrs darwin {
    setWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      /usr/bin/osascript -e 'tell application "Finder" to set desktop picture to POSIX file "${./wallpaper.jpg}"'
    '';
  };
}
