# dev-lite home cap preset: terminal UX, git, ssh, AI agents, and essential
# CLI tools. Enables only the lightweight tooling bundles — language
# toolchains and other heavy bundles stay in the "dev" cap.
{ config, lib, ... }:
{
  dotfiles = {
    agents = {
      enable = lib.mkDefault true;
      enableApiAccounts = lib.mkDefault true;
      enableProxyAccounts = lib.mkDefault true;
    };
    ssh.enable = lib.mkDefault true;
    vcs = {
      git.enable = lib.mkDefault true;
    };
    terminal.zellij.enable = lib.mkDefault true;
    shell = {
      zsh.devExtras = lib.mkDefault true;
      nushell.devExtras = lib.mkDefault true;
    };
    # Daily scripting maintenance: Nix, config files, Markdown, Typst,
    # shell, and Python.
    editor = {
      neovim.dev = lib.mkDefault true;
      config.enable = lib.mkDefault true;
      markdown.enable = lib.mkDefault true;
      nix.enable = lib.mkDefault true;
      python.enable = lib.mkDefault true;
      shell.enable = lib.mkDefault true;
      typst.enable = lib.mkDefault true;
    };

    tooling = {
      cli.enable = lib.mkDefault true;
      network.enable = lib.mkDefault true;
    };
  };

  # agenix identity (from the old secrets.nix)
  age.identityPaths = [ "${config.home.homeDirectory}/.config/agenix/key.txt" ];

  services.gpg-agent = {
    enable = lib.mkDefault true;
  };

  programs.nix-index-database.comma.enable = lib.mkDefault true;
}
