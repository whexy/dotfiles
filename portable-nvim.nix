# Portable Neovim package with bundled config and tools
# This creates a self-contained neovim that can be distributed via nix-portable
{ pkgs }:
let
  # LSP servers
  lspPackages = with pkgs; [
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

  # Formatters
  formatterPackages = with pkgs; [
    black
    nixfmt-rfc-style
    prettier
    shfmt
    stylua
    typstyle
    yamlfmt
  ];

  # Linters
  linterPackages = with pkgs; [
    golangci-lint
    shellcheck
  ];

  # Runtime dependencies for treesitter and plugins
  runtimeDeps = with pkgs; [
    tree-sitter
    gcc
    git
    ripgrep
    fd
    curl
  ];

  # All tools to be available in PATH
  allTools = lspPackages ++ formatterPackages ++ linterPackages ++ runtimeDeps;

  # The neovim config directory
  nvimConfig = ./home/dev/nvim;

  # Create a wrapper script that sets up the environment and launches neovim
  wrappedNeovim = pkgs.writeShellScriptBin "nvim" ''
    # Set up XDG directories for portable operation
    export XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"
    export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}"
    export XDG_STATE_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}"
    export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-$HOME/.cache}"

    # Create config directory and symlink our bundled config if not exists
    NVIM_CONFIG_DIR="$XDG_CONFIG_HOME/nvim"
    BUNDLED_CONFIG="${nvimConfig}"

    # If nvim config doesn't exist, symlink to our bundled config
    # If it exists and is our symlink, update it
    # If it exists and is something else, leave it alone (user's own config)
    if [ ! -e "$NVIM_CONFIG_DIR" ]; then
      mkdir -p "$XDG_CONFIG_HOME"
      ln -s "$BUNDLED_CONFIG" "$NVIM_CONFIG_DIR"
    elif [ -L "$NVIM_CONFIG_DIR" ]; then
      # It's a symlink, check if it points to a nix store path (our previous install)
      CURRENT_TARGET=$(readlink "$NVIM_CONFIG_DIR")
      if [[ "$CURRENT_TARGET" == /nix/store/* ]]; then
        rm "$NVIM_CONFIG_DIR"
        ln -s "$BUNDLED_CONFIG" "$NVIM_CONFIG_DIR"
      fi
    fi

    # Add all tools to PATH
    export PATH="${pkgs.lib.makeBinPath allTools}:$PATH"

    # Launch neovim
    exec ${pkgs.neovim}/bin/nvim "$@"
  '';

in
pkgs.symlinkJoin {
  name = "portable-nvim";
  paths = [ wrappedNeovim ];

  meta = {
    description = "Portable Neovim with whexy's config and bundled LSPs/formatters/linters";
    mainProgram = "nvim";
  };
}
