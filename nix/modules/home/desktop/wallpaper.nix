# Desktop wallpaper (cross-platform)
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.desktop;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
in
{
  config = lib.mkIf cfg.wallpaper.enable (
    let
      wallpaper = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/japamax/gnome-kde-dynamic-wallpaper-mojave/b62525499cec0d0794ace4103837284c958b976d/mojave/mojave_dynamic-0000.jpg";
        hash = "sha256-zN8lo2cSsAe88W+RyLUtXLO2Oe3YBt2AyxPPv95DomA=";
      };
    in
    {
      # Linux: swaybg paints the wallpaper; spawned by niri at startup.
      home.packages = lib.optionals (!isDarwin) [ pkgs.swaybg ];

      programs = lib.optionalAttrs (!isDarwin) {
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
      home.activation = lib.optionalAttrs isDarwin {
        setWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          /usr/bin/osascript <<'EOF'
          tell application "System Events"
            repeat with d in desktops
              set picture of d to POSIX file "${wallpaper}"
            end repeat
          end tell
          EOF
        '';
      };
    }
  );
}
