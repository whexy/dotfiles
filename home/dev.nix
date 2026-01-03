# Development home-manager configuration
{ pkgs, lib, ... }:
let
  packages = import ./packages.nix { inherit pkgs lib; };
in
{
  imports = [
    ./base.nix
    ./dev/agents.nix
    ./dev/git.nix
    ./dev/shell.nix
    ./dev/ssh.nix
    ./dev/neovim.nix
  ];

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
  };

  home.packages = packages.dev;
}
