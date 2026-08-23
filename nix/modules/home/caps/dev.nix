# dev home cap preset: full development environment.
# Package bundles live in the `tooling` and `editor` feature groups; this
# preset enables all of them. Hosts disable bundles with lib.mkForce.
{ config, lib, ... }:
{
  dotfiles = {
    agents = {
      enable = lib.mkDefault true;
      enableApiAccounts = lib.mkDefault true;
      enableProxyAccounts = lib.mkDefault true;
    };
    ssh.enable = lib.mkDefault true;
    rclone.enable = lib.mkDefault false;
    vcs = {
      git.enable = lib.mkDefault true;
    };
    terminal.zellij.enable = lib.mkDefault true;
    shell = {
      zsh.devExtras = lib.mkDefault true;
      nushell.enable = lib.mkDefault true;
      nushell.devExtras = lib.mkDefault true;
    };
    editor = {
      neovim.dev = lib.mkDefault true;
      c.enable = lib.mkDefault true;
      config.enable = lib.mkDefault true;
      go.enable = lib.mkDefault true;
      haskell.enable = lib.mkDefault false;
      javascript.enable = lib.mkDefault true;
      lua.enable = lib.mkDefault true;
      markdown.enable = lib.mkDefault true;
      nix.enable = lib.mkDefault true;
      python.enable = lib.mkDefault true;
      rust.enable = lib.mkDefault true;
      shell.enable = lib.mkDefault true;
      typst.enable = lib.mkDefault true;
      zig.enable = lib.mkDefault true;
    };

    tooling = {
      cli.enable = lib.mkDefault true;
      network.enable = lib.mkDefault true;
      extras.enable = lib.mkDefault true;
      debug.enable = lib.mkDefault true;
    };
  };

  # agenix identity (from the old secrets.nix)
  age.identityPaths = [ "${config.home.homeDirectory}/.config/agenix/key.txt" ];

  services.gpg-agent = {
    enable = lib.mkDefault true;
  };

  programs.nix-index-database.comma.enable = lib.mkDefault true;
}
