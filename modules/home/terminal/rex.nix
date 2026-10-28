# Rex terminal multiplexer: the Rex Beta app (macOS) with Ghostty's font and
# themes, and the xterm-rex terminfo entry its terminals announce.
args@{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.terminal;
  app = "/Applications/Rex Beta.app";
  terminfo = perSystem.self.rex-terminfo;
  style = import ./style.nix;
  domain = "com.superlogical.rex";

  # Rex names custom themes custom-<UUID>. Deriving the UUID from the theme
  # name keeps the ID stable across activations.
  themeId =
    name:
    let
      h = lib.toUpper (builtins.hashString "sha256" name);
      part = start: len: lib.substring start len h;
    in
    "custom-${part 0 8}-${part 8 4}-${part 12 4}-${part 16 4}-${part 20 12}";

  themes =
    pkgs.runCommand "rex-themes.json"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        specs = builtins.toJSON [
          {
            id = themeId style.darkTheme;
            name = style.darkTheme;
            appearance = "dark";
          }
          {
            id = themeId style.lightTheme;
            name = style.lightTheme;
            appearance = "light";
          }
        ];
      }
      ''
        python3 ${./rex-themes.py} \
          ${pkgs.ghostty-bin}/Applications/Ghostty.app/Contents/Resources/ghostty/themes \
          "$specs" > $out
      '';

  install = pkgs.writeShellApplication {
    name = "rex-app-install";
    text = ''
      tmp=$(mktemp -d)
      trap '/usr/bin/hdiutil detach -quiet "$tmp/mnt" 2>/dev/null || true; rm -rf "$tmp"' EXIT

      /usr/bin/curl -fsSL --retry 3 --connect-timeout 30 --speed-limit 10240 --speed-time 60 \
        -o "$tmp/Rex.dmg" \
        https://blob.superlogical.com/download/rex-app/preview/latest.dmg
      mkdir "$tmp/mnt"
      /usr/bin/hdiutil attach -quiet -nobrowse -readonly -noautoopen \
        -mountpoint "$tmp/mnt" "$tmp/Rex.dmg"
      /usr/bin/ditto "$tmp/mnt/Rex Beta.app" "$tmp/Rex Beta.app"
      /usr/bin/hdiutil detach -quiet "$tmp/mnt"

      # The download is unpinned, so only Superlogical's Developer ID vouches
      # for what gets installed.
      /usr/bin/codesign --verify --deep --strict \
        -R='anchor apple generic and identifier "com.superlogical.rex" and certificate leaf[subject.OU] = "AG92C3PT77"' \
        "$tmp/Rex Beta.app"
      mv "$tmp/Rex Beta.app" ${lib.escapeShellArg app}
    '';
  };
in
{
  config = lib.mkMerge [
    (lib.mkIf (cfg.rex.enable && pkgs.stdenv.hostPlatform.isDarwin) {
      # Superlogical ships the app only as a DMG, and its Sparkle updater
      # replaces the bundle itself, so activation installs it only when it is
      # missing. Installing as the user lets Sparkle update it without an
      # admin prompt.
      home.activation.installRexApp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -e ${lib.escapeShellArg app} ]; then
          run ${lib.getExe install} || warnEcho "Rex Beta was not installed; the next activation retries"
        fi
      '';

      # Rex puts its CLI first on PATH in its terminals, but nix-darwin's shell
      # init resets PATH to a fixed list.
      programs.zsh.initContent = lib.mkIf config.dotfiles.shell.zsh.enable (
        lib.mkAfter ''
          if [[ -n "$REX_BIN_DIR" ]]; then
            export PATH="$REX_BIN_DIR:$PATH"
          fi
        ''
      );

      # init.lua only binds keys and defines actions and hosts; the app keeps
      # its look in its defaults domain, under the keys its Settings window
      # writes. Rex reads them at launch.
      targets.darwin.defaults.${domain} = {
        "Workspace.terminalFontName" = style.font;
        "Workspace.terminalFontPointSize" = style.fontSize (
          osConfig.dotfiles.hardware.display.macbookScreen or false
        );
        "Workspace.appearance" = "dark";
        "Workspace.darkThemeID" = themeId style.darkTheme;
        "Workspace.lightThemeID" = themeId style.lightTheme;
        # The window around the panes takes the terminal theme's colors, as
        # Ghostty's titlebar does.
        "Workspace.interfaceStyle" = "useTheme";
        "Workspace.terminalOptionKeyBehavior" = "actsAsAlt";
      };

      # Rex stores its custom themes as JSON in a data value, which
      # targets.darwin.defaults cannot write. This replaces any theme added in
      # Rex's Settings.
      home.activation.rexThemes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run /usr/bin/defaults write ${domain} Workspace.customThemes \
          -data "$(/usr/bin/xxd -p ${themes} | /usr/bin/tr -d '\n')"
      '';
    })

    (lib.mkIf cfg.rex.terminfo.enable {
      # `sudo` keeps TERMINFO_DIRS, which finds the profile copy. Everything
      # else needs ~/.terminfo: Home Manager on other distros exports
      # TERMINFO_DIRS only to user services, and the Rex app starts without
      # it. Activation writes that copy because `rex terminfo setup` rewrites
      # it too.
      home.packages = [ terminfo ];
      home.activation.rexTerminfo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run --silence ${pkgs.ncurses}/bin/tic -x -o "$HOME/.terminfo" ${terminfo.src} \
          || warnEcho "xterm-rex was not installed in ~/.terminfo"
      '';
    })
  ];
}
