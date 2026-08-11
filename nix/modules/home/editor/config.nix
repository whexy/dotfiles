# Config files (YAML/TOML/JSON): language servers and formatters.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.config.enable {
    home.packages = with pkgs; [
      prettier # JSON formatter (also HTML/CSS/Markdown)
      tombi
      vscode-langservers-extracted # jsonls (also html/cssls)
      yamlfmt
      yaml-language-server
    ];
  };
}
