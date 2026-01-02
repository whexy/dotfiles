# Shell configuration (zsh, fzf, direnv, etc.)
{
  home-manager.users.whexy =
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
            (
              with builtins;
              removeAttrs (fromTOML (readFile "${pkgs.starship}/share/starship/presets/${name}.toml")) [
                "\"$schema\""
              ]
            );
        in
        {
          enable = true;
          settings =
            lib.recursiveUpdate
              (lib.mergeAttrsList [
                (getPreset "nerd-font-symbols")
                # (getPreset "gruvbox-rainbow")
                (getPreset "pure-preset")
              ])
              {
                # TODO: add config
              };
        };

      programs.zoxide = {
        enable = true;
        enableZshIntegration = true;
      };

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
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
        };

        initContent = ''
          # If devbox is configured, use the devbox environment
          [ -x "$(command -v devbox)" ] && {
            eval "$(devbox global shellenv)"
          }

          # If devbox is configured, update the autocomplete plugin
          [ -x "$(command -v devbox)" ] && {
            source <(devbox completion zsh); compdef _devbox devbox
          }

          # fzf configuration
          local TABPREVIEW='
          (
          if [ -d "$realpath" ]; then
              eza -1 -hl --icons --color=always $realpath
          elif [ -f "$realpath" ]; then
              bat --style=numbers --color=always --line-range :500 $realpath
          elif grep -q "^$word=" $HOME/.zsh_alias_cache 2>/dev/null; then
              grep "^$word=" $HOME/.zsh_alias_cache
          else
              echo ''${desc#*-- }
          fi
          )
          2>/dev/null
          '
          zstyle ':fzf-tab:*' fzf-preview $TABPREVIEW

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
        '';

        plugins = [
          {
            name = "fzf-tab";
            src = pkgs.zsh-fzf-tab;
            file = "share/fzf-tab/fzf-tab.zsh";
          }
        ];
      };
    };
}
