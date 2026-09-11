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
  nostalgiaModeFile = "${config.xdg.stateHome}/dotfiles/nostalgia";
  modernBorland = pkgs.vimUtils.buildVimPlugin {
    pname = "vim-colors-modern-borland";
    version = "2024-03-03";
    src = pkgs.fetchFromGitHub {
      owner = "letorbi";
      repo = "vim-colors-modern-borland";
      rev = "9da28b3049481ac098f555834db1607a265eb7bc";
      hash = "sha256-ybSdRHuNOTLGo39B5Q4oJLjqYlwa3pm85eVfrFcrOL8=";
    };
  };
  # Nightly Neovim tracks master, so plugins pinned by the stable channel can
  # be older than the core changes they depend on (flash.nvim's FFI hooks, for
  # example, break until the plugin adapts to a Neovim refactor). Build the
  # whole plugin set from nixpkgs-unstable whenever the editor follows
  # nightly; the stable channel stays authoritative for release Neovim.
  nixvimNixpkgs = if cfg.neovim.nightly then inputs.nixpkgs-unstable else inputs.nixpkgs;

  # Only the package comes from the nightly flake; nixvim still builds plugins
  # and the wrapper from the nixpkgs selected above.
  #
  # The neovim wrapper derives its Lua environment from `neovim-unwrapped.lua`,
  # but the Lua rocks it collects propagate that nixpkgs' LuaJIT, so the two
  # LuaJIT versions collide in buildEnv. passthru does not affect the
  # derivation hash, so realigning it keeps the substitutable nightly build.
  neovimPackage =
    if cfg.neovim.nightly then
      inputs.neovim-nightly.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
        passthru = old.passthru // {
          inherit (pkgs.unstable) luajit;
          lua = pkgs.unstable.luajit;
        };
      })
    else
      pkgs.neovim-unwrapped;
in
{
  config = lib.mkIf cfg.neovim.enable {
    programs.nixvim = {
      enable = true;
      package = neovimPackage;
      nixpkgs.source = nixvimNixpkgs.outPath;
      # Nixvim tracks the stable release while the nightly plugin set comes from
      # nixpkgs-unstable, so its release check always reports a mismatch here.
      version.enableNixpkgsReleaseCheck = !cfg.neovim.nightly;
      wrapRc = true;
      impureRtp = true;
      extraPlugins = [ modernBorland ];
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

      extraConfigLuaPre = ''
        if vim.env.SSH_CONNECTION or vim.env.SSH_TTY then
          vim.g.clipboard = "osc52"
        end
      '';

      extraConfigLuaPost = ''
        local nostalgia_mode_file = ${lib.generators.toLua { } nostalgiaModeFile}

        local function apply_dotfiles_mode()
          if vim.fn.filereadable(nostalgia_mode_file) == 1 then
            vim.g.BorlandStyle = "classic"
            vim.cmd.colorscheme("modern-borland")
          else
            vim.g.BorlandStyle = nil
            vim.cmd.colorscheme(${
              lib.generators.toLua { } (if cfg.neovim.dev then "gruvbox" else "default")
            })
          end
        end

        apply_dotfiles_mode()
        vim.api.nvim_create_autocmd("Signal", {
          pattern = "SIGUSR1",
          callback = apply_dotfiles_mode,
          desc = "Reload the dotfiles visual mode",
        })
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
