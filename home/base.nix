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
  ghostty-pkg = (if darwin then p.ghostty-bin else p.ghostty);
  ghostty-terminfo = ghostty-pkg.terminfo;
in
{
  imports = [
    ./base/htop.nix
    ./base/btop.nix
    ./base/shell.nix
    ./base/tmux.nix
    ./base/neovim.nix
  ];

  home.stateVersion = "25.11";
  home.packages =
    with pkgs;
    [
      ghostty-terminfo
      witr-pkg
      (if wsl then openssh-wsl else openssh)
      curl
      inputs.home-manager.packages.${pkgs.system}.home-manager
      jq
      mosh
      podman
      rsync
      wget
    ]
    ++ lib.optionals (!darwin) [
      git # macOS: use native git to avoid keychain prompt
    ];
}
