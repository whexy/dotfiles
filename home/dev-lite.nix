# Lightweight development home-manager configuration
# Terminal UX, git, ssh, AI agents, and essential CLI tools.
# Heavy compilers, LSPs, and formatters are in the full "dev" cap.
{
  config,
  pkgs,
  lib,
  inputs,
  darwin ? false,
  ...
}:
{
  imports = [
    ./dev/agents.nix
    ./dev/git.nix
    ./dev/hunk.nix
    ./dev/neovim.nix
    ./dev/rclone.nix
    ./dev/shell.nix
    ./dev/ssh.nix
    ./dev/zellij.nix
    ./secrets.nix
  ];

  services.gpg-agent = {
    enable = true;
  };

  programs.nix-index-database.comma.enable = true;

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

      # Quick tools
      age
      inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.agenix
      cloudflared
      fd
      file
      just
      kubectl
      lazygit
      ripgrep
      tldr
    ]
    ++ lib.optionals config.targets.genericLinux.enable [
      _1password-cli
    ]
    ++ lib.optionals darwin [
      container
    ];
}
