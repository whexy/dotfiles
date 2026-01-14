# Shell configuration (zsh, fzf, direnv, etc.)
{ pkgs, lib, ... }:
{
  programs.bat = {
    enable = true;
    extraPackages = with pkgs.bat-extras; [
      batdiff
      batman
      batgrep
      batwatch
    ];
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    icons = "auto";
    extraOptions = [
      "--group-directories-first"
      "--header"
    ];
  };

  programs.starship =
    let
      getPreset =
        name:
        with builtins;
        removeAttrs (fromTOML (readFile "${pkgs.starship}/share/starship/presets/${name}.toml")) [
          "\"$schema\""
        ];
    in
    {
      enable = true;
      settings = lib.recursiveUpdate (lib.mergeAttrsList [
        (getPreset "nerd-font-symbols")
        (getPreset "pure-preset")
      ]) { };
    };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };

  programs.zsh = {
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
        "per-directory-history"
        "sudo"
        "tmux"
      ];
    };

    shellAliases = {
      venv = "source .venv/bin/activate";
      op-signin = "eval $(op signin)";
    };

    initContent = ''
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

      # Dump aliases for fzf-tab preview (must be at end after all aliases are defined)
      mkdir -p "''${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
      alias > "''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/aliases"
    '';

    plugins = [
      {
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.zsh";
      }
    ];
  };
}
