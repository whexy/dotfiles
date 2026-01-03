# Shared package definitions for home-manager
# Used by both NixOS/Darwin modules and standalone home-manager
{ pkgs, lib }:

{
  # Base packages (minimal system tools)
  base = with pkgs;
    [
      curl
      git
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
      ghostty.terminfo
    ];

  # Development packages
  dev = with pkgs; [
    age
    cmake
    fd
    gcc
    gdb
    kubectl
    llvm
    mtr
    nodejs
    ripgrep
    rustup
    tldr
    typst
    zellij

    # Quick tools
    uv
    xh
    tree-sitter

    # Formatters & Linters
    black
    golangci-lint
    nixfmt-rfc-style
    # rustfmt  # provided by rustup
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
    nil
    ruff
    tinymist
    tombi
    typescript-language-server
    vscode-langservers-extracted
    yaml-language-server
  ];
}
