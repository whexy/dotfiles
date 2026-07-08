# Desktop wallpaper (cross-platform)
{
  lib,
  pkgs,
  darwin ? false,
  ...
}:
let
  wallpaper = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/thatmechguy/Nix-wallpapers/b189654e49d7124ec0a3367a07b3a65c976886fe/custom%20p-b.png";
    hash = "sha256-U3ByfTa9g8GANj/x0lcDueuvTZmyKoSegdZwFXp7bZQ=";
  };
in
{
  # Linux: swaybg paints the wallpaper; spawned by niri at startup.
  home.packages = lib.optionals (!darwin) [ pkgs.swaybg ];

  programs = lib.optionalAttrs (!darwin) {
    niri.settings.spawn-at-startup = [
      {
        command = [
          "swaybg"
          "--image"
          "${wallpaper}"
          "--mode"
          "fill"
        ];
      }
    ];
  };

  # macOS: tell Finder to set the desktop picture on each activation.
  home.activation = lib.optionalAttrs darwin {
    setWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      /usr/bin/osascript -e 'tell application "Finder" to set desktop picture to POSIX file "${wallpaper}"'
    '';
  };
}
