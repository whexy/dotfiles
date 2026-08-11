# Lua: language server and formatter.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.lua.enable {
    home.packages = with pkgs; [
      lua-language-server
      stylua
    ];
  };
}
