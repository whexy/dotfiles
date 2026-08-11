# dev home cap preset: full development environment.
args@{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  osConfig = args.osConfig or null;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
in
{
  dotfiles = {
    agents = {
      enable = true;
      enableApiAccounts = true;
      enableProxyAccounts = true;
    };
    ssh.enable = true;
    rclone.enable = true;
    vcs = {
      git.enable = true;
      hunk.enable = false;
    };
    terminal.zellij.enable = true;
    shell.zsh.devExtras = true;
    editor.neovim.dev = true;
  };

  # agenix identity (from the old secrets.nix)
  age.identityPaths = [ "${config.home.homeDirectory}/.config/agenix/key.txt" ];

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

      # decompressors
      unrar
      p7zip

      # Quick tools
      age
      cloudflared
      devenv
      fd
      file
      inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.agenix
      just
      kubectl
      lazygit
      nix-output-monitor
      magic-wormhole-rs
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
      mdx-language-server
      vscode-langservers-extracted
      vtsls
      yaml-language-server
      zls
    ]
    ++ lib.optionals config.targets.genericLinux.enable [
      _1password-cli
    ]
    ++ lib.optionals isDarwin [
      # packages only available on macOS
      container
    ]
    ++ lib.optionals (!isDarwin) [
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
