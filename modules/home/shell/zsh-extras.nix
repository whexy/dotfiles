# Shell configuration (zsh, fzf, direnv, etc.)
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.shell;
in
{
  config = lib.mkIf cfg.zsh.devExtras (
    let
      incusCompletionAvailable = pkgs ? incus && lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.incus;
      incusZshCompletion =
        pkgs.runCommand "incus-zsh-completion" { nativeBuildInputs = [ pkgs.incus ]; }
          ''
            export HOME=$TMPDIR
            mkdir -p $out/share/zsh/site-functions
            incus completion zsh > $out/share/zsh/site-functions/_incus
          '';
      p10kJjStatus = pkgs.stdenvNoCC.mkDerivation {
        pname = "p10k-jj-status";
        version = "2025-11-23";

        src = pkgs.fetchFromGitHub {
          owner = "xs5871";
          repo = "p10k-jj-status";
          rev = "a98672e1cd23f1010875bf6fb376a33b1740a484";
          hash = "sha256-hTKzE7hNgKwASC4RbyCW8S9F7KaTqqyLBKtkTM7Sz/w=";
        };

        installPhase = ''
          runHook preInstall

          mkdir -p $out
          cp -R . $out/
          substituteInPlace $out/p10k-jj-status.plugin.zsh \
            --replace-fail "sed -r" "sed -E"

          runHook postInstall
        '';
      };

      # A tool's zsh hook only changes with its package, so render it at build
      # time instead of running the tool on every shell start.
      zshHook =
        name:
        {
          command,
          setup ? "",
        }:
        pkgs.runCommand "${name}-zsh-hook" { } ''
          export HOME=$TMPDIR
          ${setup}
          ${command} > $out
        '';
      zoxideHook = zshHook "zoxide" {
        command = "${lib.getExe config.programs.zoxide.package} init zsh ${lib.concatStringsSep " " config.programs.zoxide.options}";
      };
      fzfHook = zshHook "fzf" { command = "${lib.getExe config.programs.fzf.package} --zsh"; };
      direnvHook = zshHook "direnv" {
        command = "${lib.getExe config.programs.direnv.package} hook zsh";
      };
      atuinHook = zshHook "atuin" {
        setup = ''
          mkdir -p $HOME/.config/atuin
          ln -s ${config.xdg.configFile."atuin/config.toml".source} $HOME/.config/atuin/config.toml
        '';
        command = "${lib.getExe config.programs.atuin.package} init zsh ${lib.escapeShellArgs config.programs.atuin.flags}";
      };
    in
    {
      # Prompt: Powerlevel10k with Pure style, configured declaratively via Nix.
      home.file = {
        ".p10k.zsh".source = ./zsh/p10k.zsh;
      }
      // lib.optionalAttrs incusCompletionAvailable {
        ".local/share/zsh/site-functions/_incus".source =
          "${incusZshCompletion}/share/zsh/site-functions/_incus";
      };

      programs = {
        # The zsh hooks of fzf, zoxide, atuin and direnv are sourced from
        # build-time renders in initContent below, at Home Manager's positions.
        fzf = {
          enable = true;
          enableZshIntegration = false;
        };
        zoxide = {
          enable = true;
          enableZshIntegration = false;
        };

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
          enableZshIntegration = false;
          settings = {
            auto_sync = true;
            sync_address = "https://atuin.at-basking.ts.net";
            update_check = false;
            search_mode = "fuzzy";
            search_mode_shell_up_key_binding = "prefix";
            filter_mode = "global";
            filter_mode_shell_up_key_binding = "workspace";
            workspaces = true;
            enter_accept = false;
            style = "compact";
            inline_height = 30;
            store_failed = true;
          };
        };

        direnv = {
          enable = true;
          enableZshIntegration = false;
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
            package = pkgs.oh-my-zsh.overrideAttrs (old: {
              patches = (old.patches or [ ]) ++ [ ./zsh/oh-my-zsh-compdump.patch ];
            });
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

            (lib.mkIf incusCompletionAvailable (
              lib.mkOrder 550 ''
                fpath=("$HOME/.local/share/zsh/site-functions" $fpath)
              ''
            ))

            # oh-my-zsh runs compinit itself (at order 800) and defaults the dump
            # to $HOME; redirect it before it is sourced.
            (lib.mkOrder 550 ''
              ZSH_COMPDUMP="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-''${HOST%%.*}-$ZSH_VERSION"
              [[ -d ''${ZSH_COMPDUMP:h} ]] || mkdir -p ''${ZSH_COMPDUMP:h}
            '')

            (lib.mkOrder 851 ''
              source ${zoxideHook}
            '')

            # Home Manager's history settings are also at 910 and come first.
            (lib.mkOrder 911 ''
              if [[ $options[zle] = on ]]; then
                source ${fzfHook}
              fi
            '')

            # After the other order-1000 hooks, and before syntax highlighting
            # (1200), which must wrap atuin's widgets.
            (lib.mkOrder 1001 ''
              source ${direnvHook}

              if [[ $options[zle] = on ]]; then
                source ${atuinHook}
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
            {
              name = "p10k-jj-status";
              src = p10kJjStatus;
              file = "p10k-jj-status.plugin.zsh";
            }
          ];
        };
      };
    }
  );
}
