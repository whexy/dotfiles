# Base home-manager configuration
{
  pkgs,
  lib,
  inputs,
  darwin ? false,
  wsl ? false,
  ...
}:
let
  p = pkgs.unstable;
  witr-pkg = p.witr;
  ghostty-pkg = if darwin then p.ghostty-bin else p.ghostty;
  ghostty-terminfo = ghostty-pkg.terminfo;
in
{
  imports = [
    inputs.agenix.homeManagerModules.default
    inputs.nix-index-database.homeModules.default
    ./options.nix
    ./rclone.nix
    ./base/htop.nix
    ./base/btop.nix
    ./base/shell.nix
    ./base/tmux.nix
    ./base/neovim.nix
  ];

  home.stateVersion = "26.05";
  home.packages =
    with pkgs;
    [
      ghostty-terminfo
      witr-pkg
      (if wsl then openssh-wsl else openssh)
      curl
      inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager
      jq
      mosh
      podman
      rsync
      wget
      nh
    ]
    ++ lib.optionals (!darwin) [
      git # macOS: use native git to avoid keychain prompt
    ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
