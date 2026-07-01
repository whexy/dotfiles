# Shell configuration (zsh, fzf, direnv, etc.)
{
  pkgs,
  lib,
  ...
}:
{
  # Prompt: Powerlevel10k with Pure style, configured declaratively via Nix.
  home.file.".p10k.zsh".source = ./zsh/p10k.zsh;

  programs = {
    fzf.enable = true;
    zoxide.enable = true;

    bat = {
      enable = true;
      extraPackages = with pkgs.bat-extras; [
        batdiff
        batman
        batgrep
        batwatch
      ];
    };

    eza = {
      enable = true;
      icons = "auto";
      extraOptions = [
        "--group-directories-first"
        "--header"
      ];
    };

    atuin = {
      enable = true;
      settings = {
        auto_sync = false;
        update_check = false;
        search_mode = "fuzzy";
        filter_mode = "global";
        enter_accept = true;
        style = "compact";
        inline_height = 30;
        store_failed = true;
      };
    };

    direnv = {
      enable = true;
      silent = true;
      nix-direnv.enable = true;
    };

    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      history = {
        save = 10000;
        size = 10000;
        share = true;
      };

      oh-my-zsh = {
        enable = true;
        theme = "";
        plugins = [
          "command-not-found"
          "docker"
          "docker-compose"
          "extract"
          "git"
          "kubectl"
          "macos"
          "sudo"
          "tmux"
        ];
      };

      shellAliases = {
        venv = "source .venv/bin/activate";
      };

      initContent = lib.mkMerge [
        # p10k instant prompt: must be near the top of zshrc, before any console output.
        (lib.mkOrder 500 ''
          if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
            source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
          fi
        '')

        # Main shell configuration (default order 1000).
        ''
          # fzf configuration
          local TABPREVIEW='
          (
          if [ -d "$realpath" ]; then
              eza -1 -hl --icons --color=always $realpath
          elif [ -f "$realpath" ]; then
              bat --style=numbers --color=always --line-range :500 $realpath
          elif grep -q "^$word=" "''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/aliases" 2>/dev/null; then
              grep "^$word=" "''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/aliases"
          else
              echo ''${desc#*-- }
          fi
          )
          2>/dev/null
          '
          zstyle ':fzf-tab:*' fzf-preview $TABPREVIEW

          # Fix case-sensitive completion: disable oh-my-zsh's case-insensitive matching
          # that incorrectly lowercases the typed prefix
          zstyle ':completion:*' matcher-list '''

          # path context-aware jump
          pd() {
            local line idx raw dir

            line=$(
              dirs -v | while read idx raw; do
                # manual tilde expansion like the reference script
                case "$raw" in
                  "~")   dir="$HOME" ;;
                  "~/"*) dir="$HOME/''${raw#"~/"}" ;;
                  "~"*)  continue ;;         # skip unsupported cases
                  *)     dir="$raw" ;;
                esac
                echo $(realpath "$dir" 2>/dev/null)
              done | fzf --height=15 --reverse --prompt="dir> " --preview 'eza -1 -hl --icons --color=always {}'
            ) || return
            [[ -n "$line" ]] && pushd "$line"
          }

          # Pin ssh socket to a fixed path
          # so tmux & zellij sessions can always get new sock without restart
          if [[ -n "$SSH_AUTH_SOCK" && "$SSH_AUTH_SOCK" == /tmp/* ]]; then
            ln -sf "$SSH_AUTH_SOCK" $HOME/.ssh/ssh-agent.sock
            export SSH_AUTH_SOCK="$HOME/.ssh/ssh-agent.sock"
          fi

          # nix run nixpkg# shortcut
          nr() {
            if [ $# -lt 1 ]; then
              echo "usage: nr <nixpkgs-package> [args...]" >&2
              return 2
            fi
            nix run "nixpkgs#$1" -- "''${@:2}"
          }

          # Dump aliases for fzf-tab preview (must be at end after all aliases are defined)
          mkdir -p "''${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
          alias > "''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/aliases"
        ''

        # p10k config: source at the end after everything is loaded.
        (lib.mkOrder 1500 ''
          [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
        '')

        # Fix fzf-tab leaking raw PROMPT variables into scrollback.
        # When fzf-tab triggers completion, it does `echoti cud1` which pushes the
        # current prompt into scrollback. If PROMPT contains unevaluated variables
        # (as with p10k, starship, etc. using promptsubst), the raw text leaks.
        # Fix: wrap the fzf-tab-complete ZLE widget to pre-evaluate PROMPT before
        # fzf runs, then restore promptsubst after completion finishes.
        (lib.mkOrder 1500 ''
          # Save the original fzf-tab-complete function body
          functions[_orig_fzf_tab_complete]=$functions[fzf-tab-complete]
          # Replace fzf-tab-complete with a wrapper
          fzf-tab-complete() {
            local _ftb_saved_prompt _ftb_saved_rprompt
            if [[ -o promptsubst ]]; then
              _ftb_saved_prompt="$PROMPT"
              _ftb_saved_rprompt="$RPROMPT"
              PROMPT="''${(e)PROMPT}"
              RPROMPT="''${(e)RPROMPT}"
              unsetopt promptsubst
            fi
            _orig_fzf_tab_complete "$@"
            local ret=$?
            if [[ -n "$_ftb_saved_prompt" ]]; then
              PROMPT="$_ftb_saved_prompt"
              RPROMPT="$_ftb_saved_rprompt"
              setopt promptsubst
            fi
            return $ret
          }
        '')
      ];

      plugins = [
        {
          name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }
        {
          name = "fzf-tab";
          src = pkgs.zsh-fzf-tab;
          file = "share/fzf-tab/fzf-tab.zsh";
        }
      ];
    };
  };
}
