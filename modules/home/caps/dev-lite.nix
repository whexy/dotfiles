# dev-lite home cap preset: terminal UX, git, ssh, AI agents, and essential
# CLI tools. Enables only the lightweight tooling bundles — language
# toolchains and other heavy bundles stay in the "dev" cap.
{
  lib,
  pkgs,
  config,
  ...
}:
{
  dotfiles = {
    agents.enable = lib.mkDefault true;
    agenticTooling = {
      transcribe.enable = lib.mkDefault true;
      wechat.enable = lib.mkDefault true;
    };
    t3code = {
      enable = lib.mkDefault true;
      pair.enable = lib.mkDefault true;
      # whexy/t3code's server, which applies programs.t3code.policy, comes
      # prebuilt from ci-cache for x86_64-linux only.
      fork.enable = lib.mkDefault (
        pkgs.stdenv.hostPlatform.system == "x86_64-linux" && config.dotfiles.t3code.server.enable
      );
    };
    ssh.enable = lib.mkDefault true;
    nix.ghTokenFlakes.enable = lib.mkDefault true;
    vcs = {
      git.enable = lib.mkDefault true;
    };
    shell = {
      zsh.devExtras = lib.mkDefault true;
      nushell.enable = lib.mkDefault true;
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
      kube.enable = lib.mkDefault true;
      appStoreConnect.enable = lib.mkDefault true;
      aws.enable = lib.mkDefault true;
      cloudflare = {
        cli.enable = lib.mkDefault true;
        apiToken.enable = lib.mkDefault true;
      };
    };
  };

  services.gpg-agent = {
    enable = lib.mkDefault true;
  };

  programs.nix-index-database.comma.enable = lib.mkDefault true;
}
