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
    monitors.htop.enable = true;
    monitors.btop.enable = true;
    terminal.tmux.enable = true;
    shell.zsh.enable = true;
    editor.neovim.enable = true;
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
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
