# Development home-manager configuration
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
      tcpdump
      mtr

      # process/fs
      lsof
      duf
      dust
      ncdu

      # Languages
      clang
      deno
      go
      nodejs
      bun
      typst
      zig
      python314

      # Language tools
      man-pages # Linux API man pages (sections 2-7)
      man-pages-posix # POSIX man pages (listen, socket, etc.)
      cmake
      gnumake
      gdb
      lldb
      llvm
      rustup
      uv

      # Quick tools
      _1password-cli
      age
      inputs.agenix.packages.${pkgs.system}.agenix
      cloudflared
      devenv
      fd
      file
      just
      kubectl
      lazygit
      qemu
      ripgrep
      sqlite
      tldr
      pkgs.unstable.tree-sitter
      watchexec
      woodpecker-cli
      xh
      yazi
      yq
      zellij

      # Formatters & Linters
      black
      golangci-lint
      nixfmt-rfc-style
      ormolu
      prettier
      shellcheck
      shfmt
      stylua
      typstyle
      yamlfmt

      # LSP
      basedpyright
      clang-tools
      gopls
      lua-language-server
      nixd
      ruff
      tinymist
      tombi
      typescript-language-server
      vscode-langservers-extracted
      yaml-language-server
      zls
    ]
    ++ lib.optionals darwin [
      # packages only available on macOS
      container
    ]
    ++ lib.optionals (!darwin) [
      # packages not available on macOS
      traceroute
      strace
    ];
}
