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
  # Deep merge (not //): the Linux/Darwin branches extend sub-attrsets like
  # `panel`, `desktop`, and `clipboard` rather than replacing them.
  dotfiles =
    lib.recursiveUpdate
      {
        terminal.ghostty.enable = lib.mkDefault true;
        browser.firefox.enable = lib.mkDefault true;
        panel.waybar.enable = lib.mkDefault (!isDarwin);
        editor.neovide.enable = lib.mkDefault true;
        clipboard.history.enable = lib.mkDefault true;
        streaming.enable = lib.mkDefault true;
        desktop.wallpaper.enable = lib.mkDefault true;
        vcs.git.opSshSigning = lib.mkDefault true;
      }
      (
        lib.optionalAttrs (!isDarwin) {
          # Linux desktop (Wayland/niri)
          wm.niri.enable = lib.mkDefault true;
          keyboard.fcitx5.enable = lib.mkDefault true;
          desktop = {
            mako.enable = lib.mkDefault true;
            macbookScreenDensity.enable = lib.mkDefault true;
          };
          clipboard.vmware.enable = lib.mkDefault true;
          panel.renpho.enable = lib.mkDefault true;
        }
        // lib.optionalAttrs isDarwin {
          # macOS desktop
          wm.aerospace.enable = lib.mkDefault true;
          keyboard.karabiner.enable = lib.mkDefault true;
          panel.sketchybar.enable = lib.mkDefault true;
        }
      );

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
