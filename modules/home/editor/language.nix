# Builds the config of an `editor.<name>` language module: `packages` (its
# toolchain) when the language is enabled, and with them, in the development
# Nixvim profile, the Tree-sitter `grammars` and the `nixvim` integration.
{ config, lib }:
name:
{
  packages ? [ ],
  grammars ? [ ],
  nixvim ? { },
}:
let
  cfg = config.dotfiles.editor;
  inherit (config.programs.nixvim.plugins.treesitter.package) builtGrammars;
in
lib.mkIf cfg.${name}.enable {
  home.packages = packages;
  programs.nixvim = lib.mkIf (cfg.neovim.enable && cfg.neovim.dev) (
    lib.mkMerge [
      { plugins.treesitter.grammarPackages = map (grammar: builtGrammars.${grammar}) grammars; }
      nixvim
    ]
  );
}
