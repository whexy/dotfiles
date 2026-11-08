# Python: toolchain, package manager, language servers, and formatter.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = import ./language.nix { inherit config lib; } "python" {
    packages = with pkgs; [
      python3 # whatever version the channel provides
      uv
    ];
    textWidth = 88;
    grammars = [ "python" ];
    nixvim = {
      lsp.servers = {
        basedpyright = {
          enable = true;
          config.settings.basedpyright.analysis.typeCheckingMode = "standard";
        };
        ruff = {
          enable = true;
        };
      };
      plugins.conform-nvim.settings.formatters_by_ft.python = [
        "ruff_fix"
        "ruff_organize_imports"
        "ruff_format"
      ];
    };
  };
}
