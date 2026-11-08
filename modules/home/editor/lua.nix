# Lua: language server and formatter.
{
  config,
  lib,
  ...
}:
{
  config = import ./language.nix { inherit config lib; } "lua" {
    grammars = [ "lua" ];
    nixvim = {
      lsp.servers.lua_ls = {
        enable = true;
        config.settings.Lua = {
          runtime.version = "LuaJIT";
          diagnostics.globals = [ "vim" ];
          telemetry.enable = false;
        };
      };
      plugins.conform-nvim.settings.formatters_by_ft.lua = [ "stylua" ];
    };
  };
}
