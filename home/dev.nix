# Development home-manager configuration
{
  pkgs,
  config,
  darwin ? false,
  ...
}:
{
  imports = [
    ./dev/agents.nix
    ./dev/git.nix
    ./dev/rclone.nix
    ./dev/shell.nix
    ./dev/ssh.nix
    ./dev/neovim.nix
  ];

  # agenix secret management
  age = {
    identityPaths = [ "${config.home.homeDirectory}/.config/agenix/key.txt" ];
    secrets.api-keys.file = ../secrets/api-keys.age;
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
  };

  home.packages =
    with pkgs;
    [
      # Network diagnostic tools
      openssl
      dig
      nmap
      tcpdump
      mtr

      # process/fs
      htop
      btop
      lsof
      duf
      dust
      ncdu

      # Languages
      clang
      deno
      go
      nodejs
      typst
      zig
      python314

      # Language tools
      cmake
      gdb
      gnumake
      llvm
      rustup
      uv

      # Quick tools
      age
      cloudflared
      devenv
      fd
      file
      just
      kubectl
      mtr
      ripgrep
      tldr
      tree-sitter
      xh
      zellij

      # Formatters & Linters
      black
      golangci-lint
      nixfmt-rfc-style
      shellcheck
      shfmt
      stylua
      typstyle
      yamlfmt
      prettier

      # LSP
      basedpyright
      clang-tools
      gopls
      lua-language-server
      nil
      ruff
      tinymist
      tombi
      typescript-language-server
      vscode-langservers-extracted
      yaml-language-server
      zls
    ]
    ++ lib.optionals (!darwin) [
      # packages not available on macOS
      traceroute
      strace
    ];
}
