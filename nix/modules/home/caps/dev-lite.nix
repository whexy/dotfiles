# dev-lite home cap preset: terminal UX, git, ssh, AI agents, and essential
# CLI tools. Heavy compilers, LSPs, and formatters are in the "dev" cap.
args@{
  config,
  pkgs,
  lib,
  inputs,
  # Injected by blueprint into every home-manager evaluation.
  perSystem,
  ...
}:
let
  osConfig = args.osConfig or null;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
in
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
      hunk.enable = false;
    };
    terminal.zellij.enable = lib.mkDefault true;
    shell.zsh.devExtras = lib.mkDefault true;
    editor.neovim.dev = lib.mkDefault true;
  };

  # agenix identity (from the old secrets.nix)
  age.identityPaths = [ "${config.home.homeDirectory}/.config/agenix/key.txt" ];

  services.gpg-agent = {
    enable = lib.mkDefault true;
  };

  programs.nix-index-database.comma.enable = lib.mkDefault true;

  home.packages =
    with pkgs;
    [
      # Network diagnostic tools
      openssl
      dig
      nmap
      mtr

      # process/fs
      lsof
      duf
      dust
      ncdu
      lldb

      # Typst (writing)
      typst
      tinymist
      typstyle

      # Config files
      nixfmt
      prettier
      shellcheck
      shfmt
      stylua
      yamlfmt

      lua-language-server
      nixd
      tombi
      vscode-langservers-extracted
      yaml-language-server

      # decompressors
      xz
      bzip2

      # Quick tools
      age
      inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.agenix
      cloudflared
      fd
      file
      just
      kubectl
      lazygit
      nix-output-monitor
      ripgrep
      tldr
    ]
    ++ lib.optionals config.targets.genericLinux.enable [
      _1password-cli
    ]
    ++ lib.optionals isDarwin [
      container
      perSystem.self.doordash-cli
    ];
}
