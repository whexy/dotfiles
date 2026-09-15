# sysadmin home cap preset: server inspection, network diagnostics, and agents.
{ config, lib, ... }:
{
  dotfiles = {
    tooling = {
      cli.enable = lib.mkDefault true;
      network.enable = lib.mkDefault true;
      debug.enable = lib.mkDefault true;
    };
    agents = {
      enable = lib.mkDefault true;
      enableApiAccounts = lib.mkDefault false;
      enableProxyAccounts = lib.mkDefault true;
    };
  };

  programs.nix-index-database.comma.enable = lib.mkDefault true;

  age.identityPaths = [ "${config.home.homeDirectory}/.config/agenix/key.txt" ];
}
