# VS Code as a Neovim front end. Settings and extensions are read-only store
# paths, so this module is their only source and the extensions listed here
# are the only ones VS Code can load.
{
  config,
  inputs,
  lib,
  pkgs,
  vimPkgs,
  ...
}:
let
  platform = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "linux";

  # The Nixvim profile's editing behavior and editing plugins, without its LSP,
  # completion, and UI plugins, which duplicate VS Code. The wrapper loads the
  # init itself, since vscode-neovim passes no `-u` without an init path.
  #
  # The Tree-sitter grammars come from the Nixvim profile, so Neovim and its
  # plugins come from the profile's package set too: grammars built for one
  # nvim-treesitter do not necessarily load in another's Neovim.
  neovim =
    (inputs.nixvim.lib.evalNixvim {
      modules = [
        ./neovim-editing.nix
        {
          nixpkgs.pkgs = vimPkgs;
          inherit (config.programs.nixvim) package;
          enableMan = false;
          luaLoader.enable = true;

          globals = {
            mapleader = " ";
            maplocalleader = ",";
          };
          opts = {
            ignorecase = true;
            smartcase = true;
          };
          plugins.treesitter.grammarPackages = config.programs.nixvim.plugins.treesitter.grammarPackages;

          # Neovim's own provider needs wl-copy or pbcopy on the extension
          # host's PATH; VS Code's clipboard API works everywhere VS Code runs.
          extraConfigLuaPre = "vim.g.clipboard = vim.g.vscode_clipboard";
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
              mode = "n";
              key = "<esc>";
              action = "<cmd>noh<cr><esc>";
              options.desc = "Escape and Clear hlsearch";
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
            # Recursive, so they reach vscode-neovim's <C-w> mappings to editor
            # groups.
            {
              mode = "n";
              key = "<leader>-";
              action = "<C-w>s";
              options = {
                remap = true;
                desc = "Split Window Below";
              };
            }
            {
              mode = "n";
              key = "<leader>|";
              action = "<C-w>v";
              options = {
                remap = true;
                desc = "Split Window Right";
              };
            }
            {
              mode = "n";
              key = "<leader>wd";
              action = "<C-w>c";
              options = {
                remap = true;
                desc = "Delete Window";
              };
            }
          ];
        }
      ];
    }).config.build.package;
in
{
  config = lib.mkIf config.dotfiles.editor.vscode.enable {
    programs.vscode = {
      enable = true;
      mutableExtensionsDir = false;
      profiles.default = {
        enableUpdateCheck = false;
        enableExtensionUpdateCheck = false;
        # Remote-SSH's extension pack (its config-file editing and Remote
        # Explorer) is listed too: VS Code cannot install it into the
        # read-only extensions directory.
        extensions = with pkgs.vscode-extensions; [
          asvetliakov.vscode-neovim
          ms-vscode-remote.remote-ssh
          ms-vscode-remote.remote-ssh-edit
          ms-vscode.remote-explorer
        ];
        userSettings = {
          # Copilot ships built in; these hide its chat, its sign-in prompts,
          # the first-run sign-in modal, and the secondary side bar that would
          # open empty without the chat.
          "chat.disableAIFeatures" = true;
          "workbench.welcomePage.experimentalOnboarding" = false;
          "workbench.secondarySideBar.defaultVisibility" = "hidden";
          "telemetry.telemetryLevel" = "off";
          "extensions.ignoreRecommendations" = true;
          "editor.lineNumbers" = "relative";

          "vscode-neovim.neovimExecutablePaths.${platform}" = lib.getExe neovim;
          # vscode-neovim does not declare Restricted Mode support, so VS Code
          # would disable it in every folder not yet trusted.
          "extensions.supportUntrustedWorkspaces"."asvetliakov.vscode-neovim".supported = true;
          # Its own extension host keeps Neovim's input handling from waiting
          # behind other extensions.
          "extensions.experimental.affinity"."asvetliakov.vscode-neovim" = 1;
        };
      };
    };
  };
}
