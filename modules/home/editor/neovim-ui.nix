# Nixvim module (not a Home Manager module) with the development profile's
# interface: colors, status and buffer lines, file tree, pickers, and
# Firenvim in the browser.
let
  style = import ../terminal/style.nix;
in
{
  colorschemes.gruvbox.enable = true;

  plugins = {
    nui.enable = true;
    web-devicons.enable = true;
    lualine.enable = true;
    bufferline = {
      enable = true;
      settings.options = {
        close_command.__raw = "function(bufnr) vim.cmd('bdelete ' .. bufnr) end";
        right_mouse_command.__raw = "function(bufnr) vim.cmd('bdelete ' .. bufnr) end";
        diagnostics = "nvim_lsp";
        always_show_bufferline = true;
        diagnostics_indicator.__raw = ''
          function(_, _, diag)
            return (diag.error and " E" .. diag.error .. " " or "")
              .. (diag.warning and " W" .. diag.warning or "")
          end
        '';
        offsets = [
          {
            filetype = "neo-tree";
            text = "Neo-tree";
            highlight = "Directory";
            text_align = "left";
          }
        ];
      };
    };
    neo-tree = {
      enable = true;
      settings = {
        source_selector.winbar = true;
        filesystem = {
          follow_current_file.enabled = true;
          filtered_items.visible = true;
          use_libuv_file_watcher = true;
        };
      };
    };
    which-key.enable = true;
    telescope.enable = true;
    indent-blankline = {
      enable = true;
      settings = {
        indent = {
          char = "|";
          tab_char = "|";
        };
        scope = {
          show_start = false;
          show_end = false;
        };
        exclude.filetypes = [
          "help"
          "lazy"
          "mason"
        ];
      };
    };
    firenvim = {
      enable = true;
      settings.localSettings.".*" = {
        takeover = "never";
        selector = ''textarea:not([readonly],[aria-readonly]),div[role="textbox"],[contenteditable="true"]'';
      };
    };
  };

  extraConfigLua = ''
    if vim.g.started_by_firenvim then vim.opt.guifont = "${style.font}:h14" end
  '';
}
