# JavaScript/TypeScript: runtimes and language server.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.javascript.enable {
    home.packages = with pkgs; [
      bun
      deno
      nodejs
      vtsls
    ];
  };
}
