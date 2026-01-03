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
    _1password-cli
    age
    clang
    cmake
    deno
    fd
    gdb
    go
    kubectl
    llvm
    mtr
    nodejs
    ripgrep
    rustup
    tldr
    typst
    zellij
    zig

    # Quick tools
    uv
    xh
    tree-sitter

    # Formatters & Linters
    black
    golangci-lint
    nixfmt-rfc-style
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
