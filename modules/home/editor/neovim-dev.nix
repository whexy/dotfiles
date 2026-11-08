# Full development Nixvim profile. Language integrations live in their
# corresponding editor language modules.
{
  config,
  lib,
  ...
}:
let
  cfg = config.dotfiles.editor;
in
{
  config = lib.mkIf (cfg.neovim.enable && cfg.neovim.dev) {
    programs.nixvim = {
      imports = [
        ./neovim-editing.nix
        ./neovim-ui.nix
        ./neovim-lsp.nix
        ./neovim-keymaps.nix
      ];

      opts = {
        exrc = true;
        secure = true;
        textwidth = 80;
        colorcolumn = "80";
        winminwidth = 5;
        list = false;
        foldtext = "v:lua.vim.fn.getline(v:foldstart) .. ' ...'";
        jumpoptions = "view";
      };

      plugins = {
        treesitter = {
          highlight.enable = true;
          indent.enable = true;
          folding.enable = true;
          grammarPackages = with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [ regex ];
        };
        yanky = {
          enable = true;
          settings.system_clipboard.sync_with_ring = false;
        };
        hardtime = {
          enable = true;
          settings.disable_mouse = false;
        };
      };

      userCommands.Run = {
        nargs = "+";
        complete = "shellcmd";
        command.__raw = ''
          function(opts)
            local buffer = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_buf_set_name(buffer, "Run Output")
            vim.cmd("botright split")
            vim.api.nvim_win_set_buf(0, buffer)
            vim.fn.jobstart(opts.args, {
              on_stdout = function(_, data) if data then vim.api.nvim_buf_set_lines(buffer, -1, -1, false, data) end end,
              on_stderr = function(_, data) if data then vim.api.nvim_buf_set_lines(buffer, -1, -1, false, data) end end,
            })
          end
        '';
      };
    };
  };
}
