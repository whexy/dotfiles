# Base home-manager configuration
{
  pkgs,
  lib,
  darwin ? false,
  wsl ? false,
  ...
}:
{
  imports = [
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
      jq
      podman
      rsync
      wget
    ]
    ++ lib.optionals (!darwin) [
      git # macOS: use native git to avoid keychain prompt
    ];
}
