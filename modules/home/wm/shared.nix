# What niri, AeroSpace and Paneru bind alike.
{ config, pkgs }:
{
  # The modifier chords the keyboard group's remappers (kanata on NixOS,
  # Karabiner on macOS) emit for held keys, in each window manager's syntax:
  #   CapsLock (held) = Hyper = Ctrl+Alt+Shift+Super
  #   Tab (held)      = Meh   = Ctrl+Alt+Super
  hyper = {
    niri = "Ctrl+Alt+Shift+Super";
    aerospace = "cmd-alt-ctrl-shift";
    paneru = "ctrl + alt + shift + cmd";
  };
  meh = {
    niri = "Ctrl+Alt+Super";
    aerospace = "cmd-alt-ctrl";
    paneru = "ctrl + alt + cmd";
  };

  # What Hyper+T opens. Rex (macOS) takes the key over ssh-window, which
  # clones the focused window's SSH destination and so works only for Ghostty
  # windows.
  terminal =
    if pkgs.stdenv.hostPlatform.isDarwin && config.dotfiles.terminal.rex.enable then
      "rex"
    else if config.programs.ssh-window.enable then
      "ssh-window"
    else
      "ghostty";

  # Meh+T raises T3 Code's desktop app.
  t3codeDesktop = config.dotfiles.t3code.enable && config.dotfiles.t3code.desktop.enable;
}
