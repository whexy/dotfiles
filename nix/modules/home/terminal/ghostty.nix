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
      themeFile = "${config.home.homeDirectory}/.config/ghostty/theme.conf";

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

        # Ask every running Ghostty instance to reload its configuration.
        if [ "$(uname)" = "Darwin" ]; then
          if ! osascript -e 'tell application "System Events" to tell (first process whose bundle identifier is "com.mitchellh.ghostty") to keystroke "," using {command down, shift down}' 2>/dev/null; then
            echo "press cmd+shift+, in Ghostty to apply the new theme" >&2
          fi
        else
          systemctl reload --user app-com.mitchellh.ghostty.service
        fi
      '';

    in
    {
      home.packages = [ ghostty-toggle-theme ];

      # Seed the mutable theme file (never overwrite an existing one).
      home.activation.ghosttyThemeFile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f "${themeFile}" ]; then
          mkdir -p "$(dirname "${themeFile}")"
          echo "theme = ${darkTheme}" > "${themeFile}"
        fi
      '';

      programs.ghostty = {
        enable = true;
        package = ghostty-pkg;
        systemd.enable = !isDarwin;

        settings = {
          config-file = themeFile;
          font-size = if macbookScreen then 16 else 14;
          font-family = "FiraCode Nerd Font";
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
              "ctrl+shift+arrow_down=jump_to_prompt:1"
              "ctrl+shift+arrow_up=jump_to_prompt:-1"
              "ctrl+alt+t=text:ghostty-toggle-theme\\n"
            ]
            ++ lib.optionals isDarwin [
              "alt+left=unbind"
              "alt+right=unbind"
              "cmd+shift+zero=set_font_size:23"
              "cmd+shift+r=reset"
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
