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
