# Base home-manager configuration
{
  pkgs,
  lib,
  inputs,
  darwin ? false,
  wsl ? false,
  ...
}:
{
  imports = [
    ./base/htop.nix
    ./base/shell.nix
    ./base/tmux.nix
    ./base/neovim.nix
  ];

  home.stateVersion = "25.11";
  home.packages =
    with pkgs;
    [
      (if darwin then ghostty-bin.terminfo else ghostty.terminfo)
      (if wsl then openssh-wsl else openssh)
      curl
      htop
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
