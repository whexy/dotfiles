# Lightweight development home-manager configuration
# Terminal UX, git, ssh, AI agents, and essential CLI tools.
# Heavy compilers, LSPs, and formatters are in the full "dev" cap.
{
  pkgs,
  inputs,
  darwin ? false,
  ...
}:
{
  imports = [
    ./secrets.nix
    ./dev/agents.nix
    ./dev/git.nix
    ./dev/rclone.nix
    ./dev/shell.nix
    ./dev/ssh.nix
    ./dev/neovim.nix
    ./dev/zellij.nix
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

      # Quick tools
      _1password-cli
      age
      inputs.agenix.packages.${pkgs.system}.agenix
      cloudflared
      fd
      file
      just
      kubectl
      lazygit
      ripgrep
      tldr
      pkgs.unstable.tree-sitter
    ]
    ++ lib.optionals darwin [
      container
    ];
}
