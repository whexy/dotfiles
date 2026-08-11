# gui home cap preset: desktop apps, Wayland/niri on Linux,
# aerospace/karabiner on macOS.
args@{
  pkgs,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
in
{
  dotfiles = {
    terminal.ghostty.enable = true;
    browser.firefox.enable = true;
    panel.waybar.enable = true;
    editor.neovide.enable = true;
    clipboard.history.enable = true;
    streaming.enable = true;
    desktop.wallpaper.enable = true;
    vcs.git.opSshSigning = true;
  }
  // lib.optionalAttrs (!isDarwin) {
    # Linux desktop (Wayland/niri)
    wm.niri.enable = true;
    keyboard.fcitx5.enable = true;
    desktop = {
      mako.enable = true;
      macbookScreenDensity.enable = true;
    };
    clipboard.vmware.enable = true;
    panel.renpho.enable = true;
  }
  // lib.optionalAttrs isDarwin {
    # macOS desktop
    wm.aerospace.enable = true;
    keyboard.karabiner.enable = true;
  };

  home.packages =
    with pkgs;
    [
      moonlight-qt
    ]
    ++ lib.optionals (!isDarwin) [
      # Linux only
      nautilus # required by xdg-desktop-portal-gnome for FileChooser
      obsidian
      pavucontrol # PipeWire/Pulse per-stream routing GUI (waybar audio module)
      vlc
    ]
    ++ lib.optionals (!isDarwin && pkgs.stdenv.hostPlatform.system != "aarch64-linux") [
      # x86-64 Linux only
      zoom-us
    ];
}
