# Editor group: Neovim, Neovide, and per-language editing support. Each
# `editor.<language>.enable` installs the language toolchain together with
# its language servers and formatters.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  options.dotfiles.editor = {
    neovim = {
      enable = lib.mkEnableOption "Neovim";
      dev = lib.mkEnableOption "the full-featured development Neovim setup";
      nightly = lib.mkEnableOption "the nightly Neovim build from neovim-nightly-overlay";
    };
    neovide.enable = lib.mkEnableOption "Neovide (Neovim GUI)";

    c.enable = lib.mkEnableOption "C/C++ editing support";
    config.enable = lib.mkEnableOption "config file (YAML/TOML/JSON) editing support";
    go.enable = lib.mkEnableOption "Go editing support";
    haskell.enable = lib.mkEnableOption "Haskell editing support";
    javascript.enable = lib.mkEnableOption "JavaScript/TypeScript editing support";
    lua.enable = lib.mkEnableOption "Lua editing support";
    markdown.enable = lib.mkEnableOption "Markdown editing support";
    nix.enable = lib.mkEnableOption "Nix editing support";
    python.enable = lib.mkEnableOption "Python editing support";
    rust.enable = lib.mkEnableOption "Rust editing support";
    shell.enable = lib.mkEnableOption "shell script editing support";
    typst.enable = lib.mkEnableOption "Typst editing support";
    zig.enable = lib.mkEnableOption "Zig editing support";
  };

  imports = [
    inputs.nixvim.homeModules.nixvim
    ./neovim.nix
    ./neovim-dev.nix
    ./neovide.nix
    ./c.nix
    ./config.nix
    ./go.nix
    ./haskell.nix
    ./javascript.nix
    ./lua.nix
    ./markdown.nix
    ./nix.nix
    ./python.nix
    ./rust.nix
    ./shell.nix
    ./typst.nix
    ./zig.nix
  ];

  # Nightly Neovim tracks master, so plugins pinned by the stable channel can
  # be older than the core changes they depend on (flash.nvim's FFI hooks, for
  # example, break until the plugin adapts to a Neovim refactor). Nixvim and
  # the plugins built outside its option set all come from this package set,
  # so the whole plugin set follows nixpkgs-unstable whenever the editor
  # follows nightly; the stable channel stays authoritative for release Neovim.
  config._module.args.vimPkgs = if config.dotfiles.editor.neovim.nightly then pkgs.unstable else pkgs;
}
