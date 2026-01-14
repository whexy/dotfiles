# Base home-manager configuration
{
  pkgs,
  lib,
  wsl ? false,
  ...
}:
{
  imports = [
    ./base/shell.nix
    ./base/tmux.nix
    ./base/vim.nix
  ];

  home.stateVersion = "25.11";
  home.packages =
    with pkgs;
    [
      curl
      htop
      jq
      (if wsl then openssh-wsl else openssh)
      podman
      rsync
      vim
      wget
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      ghostty-bin.terminfo
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      git
      ghostty.terminfo
    ];
}
