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

      # Quick tools
      age
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
      tree-sitter
      watchexec
      woodpecker-cli
      xh
      yq
      zellij

      # Formatters & Linters
      black
      golangci-lint
      hlint
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
      haskell-language-server
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
    ++ lib.optionals (!darwin) [
      # packages not available on macOS
      traceroute
      strace
    ];
}
