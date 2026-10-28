# Rex terminal multiplexer: the Rex Beta app (macOS) and the xterm-rex
# terminfo entry its terminals announce.
{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.terminal;
  app = "/Applications/Rex Beta.app";
  terminfo = perSystem.self.rex-terminfo;

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
