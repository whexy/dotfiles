# base home cap preset: terminal essentials every user gets.
#
# Assigns dotfiles.* home options (plain priority); users and hosts can
# override individual options with lib.mkForce.
args@{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  osConfig = args.osConfig or null;
  p = pkgs.unstable;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
  isWsl = osConfig != null && osConfig.dotfiles.host.wsl;
  witr-pkg = p.witr;
  ghostty-pkg = if isDarwin then p.ghostty-bin else p.ghostty;
  ghostty-terminfo = ghostty-pkg.terminfo;
in
{
  dotfiles = {
    monitors.htop.enable = lib.mkDefault true;
    monitors.btop.enable = lib.mkDefault true;
    terminal.tmux.enable = lib.mkDefault true;
    shell.zsh.enable = lib.mkDefault true;
    editor.neovim.enable = lib.mkDefault true;
  };

  home.stateVersion = "26.05";
  home.packages =
    with pkgs;
    [
      ghostty-terminfo
      witr-pkg
      (if isWsl then openssh-wsl else openssh)
      curl
      inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager
      jq
      mosh
      podman
      rsync
      wget
      nh
      unzip
      zstd
    ]
    ++ lib.optionals (!isDarwin) [
      git # macOS: use native git to avoid keychain prompt
    ];

  nix.gc = {
    automatic = lib.mkDefault true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
