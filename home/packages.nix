# Shared package definitions for home-manager
# Used by both NixOS/Darwin modules and standalone home-manager
{ pkgs, lib }:

{
  # Base packages (minimal system tools)
  base =
    with pkgs;
    [
      curl
      htop
      jq
      openssh
      podman
      rsync
      vim
      wget
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      ghostty-bin.terminfo
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      git
      ghostty.terminfo
    ];

  # Development packages
  dev = with pkgs; [
    # Languages
    clang
    deno
    go
    nodejs
    typst
    zig

    # Language tools
    cmake
    gdb
    gnumake
    llvm
    rustup
    uv

    # Quick tools
    _1password-cli
    age
    fd
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
  ];
}
