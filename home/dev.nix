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
      bun
      typst
      zig
      python314

      # Language tools
      cmake
      gnumake
      gdb
      lldb
      llvm
      rustup
      uv

      # Haskell
      haskell-language-server
      ormolu
      hlint

      # Quick tools
      age
      cloudflared
      devenv
      fd
      file
      just
      kubectl
      lazygit
      ripgrep
      sqlite
      tldr
      tree-sitter
      woodpecker-cli
      watchexec
      xh
      yq
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
