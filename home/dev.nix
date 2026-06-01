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
      dig
      iperf3
      mtr
      nmap
      openssl
      socat
      tcpdump

      # process/fs
      duf
      dust
      lsof
      ncdu

      # Languages
      bun
      clang
      deno
      go
      nodejs
      python314
      typst
      zig

      # Language tools
      cmake
      gdb
      gnumake
      lldb
      llvm
      man-pages # Linux API man pages (sections 2-7)
      man-pages-posix # POSIX man pages (listen, socket, etc.)
      rustup
      uv

      # Quick tools
      _1password-cli
      age
      cloudflared
      devenv
      fd
      file
      inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.agenix
      just
      kubectl
      lazygit
      magic-wormhole-rs
      pkgs.unstable.tree-sitter
      qemu
      ripgrep
      sqlite
      tldr
      watchexec
      woodpecker-cli
      xh
      yazi
      yq

      # Formatters & Linters
      black
      golangci-lint
      nixfmt
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
      vscode-langservers-extracted
      vtsls
      yaml-language-server
      zls
    ]
    ++ lib.optionals darwin [
      # packages only available on macOS
      container
    ]
    ++ lib.optionals (!darwin) [
      # packages only available on Linux
      bpftrace
      ltrace
      perf
      rr
      strace
      traceroute
    ]
    ++ lib.optionals (pkgs.stdenv.isx86_64 && pkgs.stdenv.isLinux) [
      # packages only available on x86_64 Linux
      aflplusplus
      valgrind
    ];
}
