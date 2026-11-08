# Nix: language server and formatter.
{
  config,
  lib,
  ...
}:
{
  config = import ./language.nix { inherit config lib; } "nix" {
    grammars = [ "nix" ];
    nixvim = {
      lsp.servers.nixd = {
        enable = true;
      };
      plugins.conform-nvim.settings.formatters_by_ft.nix = [ "nixfmt" ];
    };
  };
}
