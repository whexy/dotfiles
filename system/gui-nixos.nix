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

  # Kanata: remap CapsLock to Hyper / CapsLock,
  #         remap Tab to Meh / Tab.
  # Uses tap-hold-press so the modifier activates instantly when another
  # key is pressed, and the tap fires on release if pressed alone.
  # This mirrors the Karabiner setup on macOS.
  services.kanata = {
    enable = true;
    keyboards.default = {
      devices = [ ]; # empty = all keyboards
      extraDefCfg = "process-unmapped-keys yes";
      config = ''
        (defsrc
          caps tab
        )
        (defvar
          tap-time 200
          hold-time 200
        )
        (defalias
          hyper (tap-hold-press $tap-time $hold-time caps (multi lctl lalt lsft lmet))
          meh   (tap-hold-press $tap-time $hold-time tab  (multi lctl lalt lmet))
        )
        (deflayer default
          @hyper @meh
        )
      '';
    };
  };
}
