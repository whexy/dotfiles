# Desktop wallpaper (cross-platform)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.desktop;
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
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

      # A definition of any setting makes niri-flake write a config, so the
      # whole settings value is conditional.
      programs.niri.settings = lib.mkIf (!isDarwin) {
        spawn-at-startup = [
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

      # macOS: tell System Events to set the desktop picture on each
      # activation. With no GUI login session, `launchctl asuser` runs
      # activation in the background user domain, where apps cannot launch
      # (-10810); an unattended switch must not fail for a wallpaper.
      home.activation.setWallpaper = lib.mkIf isDarwin (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run /usr/bin/osascript <<'EOF' || warnEcho "The desktop picture was not set; the next activation retries"
          tell application "System Events"
            repeat with d in desktops
              set picture of d to POSIX file "${wallpaper}"
            end repeat
          end tell
          EOF
        ''
      );
    }
  );
}
