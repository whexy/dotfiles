# Ghostty terminal configuration
args@{
  pkgs,
  lib,
  config,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.terminal;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
in
{
  config = lib.mkIf cfg.ghostty.enable (
    let
      ghostty-pkg = if isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
      macbookScreen = osConfig.dotfiles.hardware.display.macbookScreen or false;

      # Ghostty has no action to switch themes, and its built-in light/dark
      # selection follows the OS theme. Instead, the theme lives in a small
      # mutable file (theme.conf, included via `config-file`) that the
      # ghostty-toggle-theme script rewrites before asking Ghostty to reload
      # its config. A keybind types that command into the shell, giving a
      # keyboard-driven, OS-independent theme toggle.
      darkTheme = "Gruvbox Dark";
      # lightTheme = "Catppuccin Latte";
      lightTheme = "Gruvbox Light";
      themeFile = "${config.xdg.configHome}/ghostty/theme.conf";
      modeFile = "${config.xdg.configHome}/ghostty/mode.conf";
      nostalgiaModeFile = "${config.xdg.stateHome}/dotfiles/nostalgia";
      modernFont = "FiraCode Nerd Font";
      nostalgiaFont = "Perfect DOS VGA 437 Nerd Font";

      reloadGhostty = ''
        if [ "$(uname)" = "Darwin" ]; then
          if ! osascript -e 'tell application "System Events" to tell (first process whose bundle identifier is "com.mitchellh.ghostty") to keystroke "," using {command down, shift down}' 2>/dev/null; then
            echo "press cmd+shift+, in Ghostty to apply the new mode" >&2
          fi
        else
          systemctl reload --user app-com.mitchellh.ghostty.service
        fi
      '';

      notifyNeovim = ''
        runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        if [ -d "$runtime_dir" ]; then
          find "$runtime_dir" -maxdepth 1 -type s -name 'nvim.*' -print0 2>/dev/null \
            | while IFS= read -r -d "" socket; do
                pid="''${socket##*.}"
                if [[ "$pid" =~ ^[0-9]+$ ]]; then
                  kill -USR1 "$pid" 2>/dev/null || true
                fi
              done
        fi
      '';

      ghostty-nostalgia = pkgs.writeShellScriptBin "ghostty-nostalgia" ''
        mode_file="''${GHOSTTY_MODE_FILE:-$HOME/.config/ghostty/mode.conf}"
        state_file="''${NOSTALGIA_MODE_FILE:-${nostalgiaModeFile}}"

        mkdir -p "$(dirname "$mode_file")" "$(dirname "$state_file")"
        printf 'font-family = %s\n' "${nostalgiaFont}" > "$mode_file"
        : > "$state_file"
        echo "ghostty mode -> nostalgia"

        ${reloadGhostty}
        ${notifyNeovim}
      '';

      ghostty-modern = pkgs.writeShellScriptBin "ghostty-modern" ''
        mode_file="''${GHOSTTY_MODE_FILE:-$HOME/.config/ghostty/mode.conf}"
        state_file="''${NOSTALGIA_MODE_FILE:-${nostalgiaModeFile}}"

        mkdir -p "$(dirname "$mode_file")"
        printf 'font-family = %s\n' "${modernFont}" > "$mode_file"
        rm -f "$state_file"
        echo "ghostty mode -> modern"

        ${reloadGhostty}
        ${notifyNeovim}
      '';

      ghostty-toggle-theme = pkgs.writeShellScriptBin "ghostty-toggle-theme" ''
        theme_file="''${GHOSTTY_THEME_FILE:-$HOME/.config/ghostty/theme.conf}"
        dark="${darkTheme}"
        light="${lightTheme}"

        current=$(sed -n 's/^[[:space:]]*theme[[:space:]]*=[[:space:]]*//p' "$theme_file" 2>/dev/null | head -n1)
        if [ "$current" = "$dark" ]; then
          next="$light"
        else
          next="$dark"
        fi

        printf 'theme = %s\n' "$next" > "$theme_file"
        echo "ghostty theme -> $next"

        ${reloadGhostty}
      '';

    in
    {
      home.packages = [
        ghostty-modern
        ghostty-nostalgia
        ghostty-toggle-theme
      ];

      # Mutable includes keep runtime mode switches outside Home Manager's
      # immutable Ghostty config while preserving the selected mode on rebuild.
      home.activation.ghosttyMutableConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f "${themeFile}" ]; then
          mkdir -p "$(dirname "${themeFile}")"
          echo "theme = ${darkTheme}" > "${themeFile}"
        fi
        if [ ! -f "${modeFile}" ]; then
          mkdir -p "$(dirname "${modeFile}")"
          echo "font-family = ${modernFont}" > "${modeFile}"
        fi
      '';

      programs.ghostty = {
        enable = true;
        package = ghostty-pkg;
        systemd.enable = !isDarwin;

        settings = {
          config-file = [
            themeFile
            modeFile
          ];
          font-size = if macbookScreen then 16 else 14;
          background-opacity = 0.90;
          background-blur = true;

          # Allow OSC 9 / OSC 777 sequences (emitted by tools like OpenCode over SSH)
          # to trigger desktop notifications in Ghostty.
          desktop-notifications = true;

          notify-on-command-finish = "unfocused";
          notify-on-command-finish-action = "bell,notify";

          keybind =
            lib.optionals (!isDarwin) [
              "ctrl+shift+zero=set_font_size:23"
              "ctrl+shift+r=reset"
              "ctrl+shift+e=write_screen_file:open"
              "ctrl+shift+arrow_down=jump_to_prompt:1"
              "ctrl+shift+arrow_up=jump_to_prompt:-1"
              "ctrl+alt+t=text:ghostty-toggle-theme\\n"
            ]
            ++ lib.optionals isDarwin [
              "alt+left=unbind"
              "alt+right=unbind"
              "cmd+shift+zero=set_font_size:23"
              "cmd+shift+r=reset"
              "cmd+shift+e=write_screen_file:open"
              "cmd+shift+arrow_down=jump_to_prompt:1"
              "cmd+shift+arrow_up=jump_to_prompt:-1"
              "cmd+shift+comma=reload_config"
              "cmd+shift+t=text:ghostty-toggle-theme\\n"
            ];
        }
        // lib.optionalAttrs isDarwin {
          macos-option-as-alt = true;
          window-decoration = "auto";
        }
        // lib.optionalAttrs (!isDarwin) {
          window-decoration = "none";
        };
      };
    }
  );
}
