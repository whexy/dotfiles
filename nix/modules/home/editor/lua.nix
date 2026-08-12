# Lua: language server and formatter.
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.lua.enable {
    programs.nixvim = lib.mkIf config.dotfiles.editor.neovim.dev {
      plugins.treesitter.grammarPackages =
        with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [ lua ];
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
