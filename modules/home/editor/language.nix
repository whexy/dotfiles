# Builds the config of an `editor.<name>` language module: `packages` (its
# toolchain) when the language is enabled, and with them, in the development
# Nixvim profile, the Tree-sitter `grammars`, the `nixvim` integration, and
# the `textWidth` of the filetype named after the language.
{ config, lib }:
name:
{
  packages ? [ ],
  grammars ? [ ],
  nixvim ? { },
  textWidth ? null,
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
      (lib.mkIf (textWidth != null) {
        autoGroups.editor_width.clear = true;
        autoCmd = [
          {
            event = [ "FileType" ];
            pattern = [ name ];
            group = "editor_width";
            callback.__raw = "function() vim.opt_local.colorcolumn = '${toString textWidth}'; vim.opt_local.textwidth = ${toString textWidth} end";
          }
        ];
      })
    ]
  );
}
