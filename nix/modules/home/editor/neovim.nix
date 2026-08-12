# Minimal Nixvim configuration shared by base and development profiles.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.editor;
in
{
  config = lib.mkIf cfg.neovim.enable {
    programs.nixvim = {
      enable = true;
      package = pkgs.neovim-unwrapped;
      nixpkgs.source = inputs.nixpkgs.outPath;
      wrapRc = true;
      impureRtp = true;
      defaultEditor = false;
      viAlias = true;
      vimAlias = true;

      globals = {
        mapleader = " ";
        maplocalleader = ",";
      };

      opts = {
        number = true;
        relativenumber = true;
        confirm = true;
        undofile = true;
        undolevels = 1000000;
        mouse = "a";
        expandtab = true;
        shiftwidth = 2;
        tabstop = 2;
        shiftround = true;
        autoindent = true;
        smartindent = true;
        formatoptions = "jcroqlnt";
        ignorecase = true;
        smartcase = true;
        inccommand = "nosplit";
        grepprg = "rg --vimgrep";
        grepformat = "%f:%l:%c:%m";
        cursorline = true;
        signcolumn = "yes";
        ruler = true;
        laststatus = if cfg.neovim.dev then 3 else 2;
        termguicolors = true;
        showmode = false;
        scrolloff = 4;
        sidescrolloff = 8;
        splitbelow = true;
        splitright = true;
        splitkeep = "screen";
        wrap = false;
        linebreak = true;
        foldmethod = "indent";
        foldlevel = 99;
        virtualedit = "block";
        wildmode = "longest:full,full";
      };

      autoCmd = [
        {
          event = [ "TextYankPost" ];
          callback.__raw = ''
            function()
              local event = vim.v.event
              if event.operator == "y" and event.regname == "" then
                vim.fn.setreg("+", event.regcontents, event.regtype)
              end
            end
          '';
        }
      ];

      keymaps = [
        {
          mode = [
            "n"
            "x"
          ];
          key = "j";
          action = "v:count == 0 ? 'gj' : 'j'";
          options = {
            expr = true;
            silent = true;
            desc = "Down";
          };
        }
        {
          mode = [
            "n"
            "x"
          ];
          key = "k";
          action = "v:count == 0 ? 'gk' : 'k'";
          options = {
            expr = true;
            silent = true;
            desc = "Up";
          };
        }
        {
          mode = "n";
          key = "<C-h>";
          action = "<C-w>h";
          options.desc = "Move to left window";
        }
        {
          mode = "n";
          key = "<C-j>";
          action = "<C-w>j";
          options.desc = "Move to below window";
        }
        {
          mode = "n";
          key = "<C-k>";
          action = "<C-w>k";
          options.desc = "Move to above window";
        }
        {
          mode = "n";
          key = "<C-l>";
          action = "<C-w>l";
          options.desc = "Move to right window";
        }
        {
          mode = [
            "i"
            "n"
            "s"
          ];
          key = "<esc>";
          action.__raw = ''
            function()
              vim.cmd("noh")
              return "<esc>"
            end
          '';
          options = {
            expr = true;
            desc = "Escape and Clear hlsearch";
          };
        }
        {
          mode = [
            "i"
            "x"
            "n"
            "s"
          ];
          key = "<C-s>";
          action = "<cmd>w<cr><esc>";
          options.desc = "Save File";
        }
        {
          mode = "x";
          key = "<";
          action = "<gv";
        }
        {
          mode = "x";
          key = ">";
          action = ">gv";
        }
        {
          mode = "n";
          key = "<leader>-";
          action = "<C-W>s";
          options.desc = "Split Window Below";
        }
        {
          mode = "n";
          key = "<leader>|";
          action = "<C-W>v";
          options.desc = "Split Window Right";
        }
        {
          mode = "n";
          key = "<leader>wd";
          action = "<C-W>c";
          options.desc = "Delete Window";
        }
      ];

      extraConfigLuaPre = lib.mkIf (!cfg.neovim.dev) ''
        local function paste_from_unnamed()
          local lines = vim.split(vim.fn.getreg(""), "\n", { plain = true })
          return { #lines > 0 and lines or { "" }, vim.fn.getregtype(""):sub(1, 1) }
        end

        vim.g.clipboard = {
          name = "OSC 52",
          copy = {
            ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
            ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
          },
          paste = { ["+"] = paste_from_unnamed, ["*"] = paste_from_unnamed },
        }
      '';
    };

    home.sessionVariables =
      let
        nvim = lib.getExe config.programs.nixvim.build.package;
      in
      {
        EDITOR = nvim;
        VISUAL = nvim;
        SUDO_EDITOR = nvim;
      };
  };
}
