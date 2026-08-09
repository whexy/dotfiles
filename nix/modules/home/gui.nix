# GUI systems home-manager configuration
{
  lib,
  pkgs,
  darwin ? false,
  ...
}:
{
  imports = [
    ./gui/clipboard.nix
    ./gui/ghostty.nix
    ./gui/git.nix
    ./gui/waybar.nix
    ./gui/firefox.nix
    ./gui/streaming.nix
    ./gui/wallpaper.nix
  ]
  ++ lib.optionals (!darwin) [
    # Linux system use Niri as WM
    ./gui/niri.nix
    # Input method (fcitx5 + rime)
    ./gui/fcitx5.nix
    # Desktop notification daemon (mako)
    ./gui/mako.nix
    # VMware host<->guest clipboard (no-op on non-VMware hosts)
    ./gui/vmware.nix
    # Renpho smart-scale CLI + waybar pill (wires the renpho-health flake)
    ./gui/renpho.nix
    # GTK DPI compensation on hosts sharing a MacBook Retina panel
    # (no-op when hardware.display.macbookScreen is not enabled)
    ./gui/macbook-screen-density.nix
  ]
  ++ lib.optionals darwin [
    # MacOS system enable aerospace for WM-like experience
    ./gui/aerospace.nix
    ./gui/karabiner.nix
  ];

  home.packages =
    with pkgs;
    [
      moonlight-qt
      neovide
    ]
    ++ lib.optionals (!darwin) [
      # Linux only
      nautilus # required by xdg-desktop-portal-gnome for FileChooser
      obsidian
      pavucontrol # PipeWire/Pulse per-stream routing GUI (waybar audio module)
      vlc
    ]
    ++ lib.optionals (!darwin && pkgs.stdenv.hostPlatform.system != "aarch64-linux") [
      # x86-64 Linux only
      zoom-us
    ];
}
