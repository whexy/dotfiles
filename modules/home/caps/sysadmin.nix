# sysadmin home cap preset: server inspection, network diagnostics, and agents.
{ lib, ... }:
{
  dotfiles = {
    tooling = {
      cli.enable = lib.mkDefault true;
      network.enable = lib.mkDefault true;
      debug.enable = lib.mkDefault true;
      kube.enable = lib.mkDefault true;
    };
    agents = {
      enable = lib.mkDefault true;
    };
  };

  programs.nix-index-database.comma.enable = lib.mkDefault true;
}
