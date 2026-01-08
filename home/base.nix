# Base home-manager configuration
{ pkgs, lib, ... }:
{
  imports = [
    ./base/fish.nix
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
      openssh
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
