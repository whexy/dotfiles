# GUI NixOS system configuration
{ pkgs, ... }:
{
  fonts.packages = [
    (pkgs.nerd-fonts.fira-code)
    (pkgs.nerd-fonts.jetbrains-mono)
  ];

  # Required for xdg-desktop-portal with home-manager
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  # Kanata: remap CapsLock to Hyper (held) / CapsLock (tapped),
  #         remap Tab to Meh (held) / Tab (tapped).
  # This mirrors the Karabiner setup on macOS.
  services.kanata = {
    enable = true;
    keyboards.default = {
      devices = [ ]; # empty = all keyboards
      config = ''
        (defsrc
          caps tab
        )
        (defvar
          tap-time 120
          hold-time 1
        )
        (defalias
          hyper (tap-hold $tap-time $hold-time caps (multi lctl lalt lsft lmet))
          meh   (tap-hold $tap-time $hold-time tab  (multi lctl lalt lmet))
        )
        (deflayer default
          @hyper @meh
        )
      '';
    };
  };
}
