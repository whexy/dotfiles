# Development home-manager configuration
{ pkgs, ... }:
{
  imports = [
    ./dev/agents.nix
    ./dev/git.nix
    ./dev/shell.nix
    ./dev/ssh.nix
    ./dev/neovim.nix
  ];

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
  };

  home.packages = with pkgs; [
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
    _1password-cli
    age
    fd
    devbox
    devenv
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
