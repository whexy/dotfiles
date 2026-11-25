# Rex terminal multiplexer: the Rex app (macOS) with Ghostty's font and
# themes and the flake's Rex hosts, the xterm-rex terminfo entry its terminals
# announce, and Rex's personal server for Linux homes.
args@{
  config,
  lib,
  pkgs,
  perSystem,
  inputs,
  flake,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.terminal;
  relay = config.dotfiles.tailnetRelay;
  rex = inputs.rex.packages.${pkgs.stdenv.hostPlatform.system}.rex;
  tailnetNode = cfg.rex.server.hostName != null;

  serve = pkgs.writeShellScript "rex-server" ''
    args=(
      server run
      --tailscale
      --tailscale-hostname ${lib.escapeShellArg cfg.rex.server.hostName}
      # Tagged nodes have no owner, so the tailnet policy alone admits callers.
      --tailscale-allow-tailnet-members
      ${lib.concatMapStringsSep " " (
        tag: "--tailscale-advertise-tag ${lib.escapeShellArg tag}"
      ) relay.tags}
    )
    # Rex reads the key only until the node first joins. A bare client
    # secret mints an ephemeral key, and Tailscale removes an ephemeral node
    # soon after it goes offline, taking the saved identity with it.
    secret="${config.age.secrets.tailnet-relay-oauth.path}"
    if key=$(${lib.getExe' pkgs.coreutils "cat"} "$secret" 2>/dev/null) && [ -n "$key" ]; then
      exec ${lib.getExe rex} "''${args[@]}" --tailscale-auth-key-file - <<<"$key?ephemeral=false&preauthorized=true"
    fi
    exec ${lib.getExe rex} "''${args[@]}"
  '';
  app = "/Applications/Rex.app";
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

  # The app installs its server, with the CLI, under Application Support and
  # updates it there; the Current link follows each update.
  appRex = "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex";
  appCli = pkgs.writeShellScriptBin "rex" ''
    exec "${appRex}" "$@"
  '';

  # The app's server reads init.lua, so its host list declares the flake's
  # hosts. A host that fails Rex's check would be left out without a word.
  hosts = import ./rex-hosts.nix {
    inherit lib flake;
    self = osConfig.dotfiles.host.hostName or null;
  };
  initLua =
    pkgs.runCommand "rex-init.lua"
      {
        nativeBuildInputs = [
          rex
          pkgs.jq
        ];
        text = lib.concatMapStrings (host: "rex.host(${lib.generators.toLua { } host})\n") hosts;
        passAsFile = [ "text" ];
      }
      ''
        cp "$textPath" init.lua
        HOME=$TMPDIR rex --autostart=false config check --json init.lua > check.json
        if ! jq -e '.diagnostics // [] | length == 0' check.json >/dev/null; then
          jq . check.json >&2
          exit 1
        fi
        mv init.lua $out
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
      /usr/bin/ditto "$tmp/mnt/Rex.app" "$tmp/Rex.app"
      /usr/bin/hdiutil detach -quiet "$tmp/mnt"

      # The download is unpinned, so only Superlogical's Developer ID vouches
      # for what gets installed.
      /usr/bin/codesign --verify --deep --strict \
        -R='anchor apple generic and identifier "com.superlogical.rex" and certificate leaf[subject.OU] = "AG92C3PT77"' \
        "$tmp/Rex.app"
      mv "$tmp/Rex.app" ${lib.escapeShellArg app}
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
          run ${lib.getExe install} || warnEcho "Rex was not installed; the next activation retries"
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

      dotfiles.launcher.alfred.workflows.rex = pkgs.callPackage ./rex-alfred/workflow.nix { };
    })

    (lib.mkIf (cfg.rex.enable && pkgs.stdenv.hostPlatform.isDarwin) {
      home = {
        # T3 Code's server and other programs outside Rex's terminals find
        # the app's CLI on the profile.
        packages = [ appCli ];
        # Rex reads init.lua only at start and on `rex config reload`.
        activation.rexConfigReload = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          if ${lib.getExe appCli} --autostart=false server status >/dev/null 2>&1; then
            run ${lib.getExe appCli} --autostart=false config reload >/dev/null \
              || warnEcho "Rex did not reload init.lua; run rex config reload"
          fi
        '';
      };
      xdg.configFile."rex/init.lua".source = initLua;
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

    (lib.mkIf cfg.rex.server.enable {
      assertions = [
        {
          assertion = pkgs.stdenv.hostPlatform.isLinux;
          message = "dotfiles.terminal.rex.server runs a systemd user service; on macOS the Rex app runs the server.";
        }
        {
          assertion = tailnetNode -> relay.enable;
          message = "dotfiles.terminal.rex.server.hostName joins the tailnet with the tailnet relay's OAuth client, so it needs dotfiles.tailnetRelay.";
        }
      ];

      home.packages = [ rex ];
      # Rex over ssh:// looks for `rex` in ~/.local/bin when the remote
      # shell's PATH lacks it.
      home.file.".local/bin/rex" = lib.mkIf (lib.hasPrefix "ssh://" (toString cfg.rex.route)) {
        source = lib.getExe rex;
      };

      systemd.user.services.rex = {
        Unit = {
          Description =
            if tailnetNode then
              "Rex server, on the tailnet as ${cfg.rex.server.hostName}"
            else
              "Rex personal server";
          # A restart ends every session, so a switch leaves the running
          # server on its version until it next starts.
          X-SwitchMethod = "keep-old";
        }
        // lib.optionalAttrs tailnetNode {
          After = [ "agenix.service" ];
          Wants = [ "agenix.service" ];
        };
        Service = {
          Type = "notify";
          NotifyAccess = "main";
          ExecStart = if tailnetNode then "${serve}" else "${lib.getExe rex} server run";
          Environment = [
            # The trailing empty element keeps the system terminfo directories.
            "TERMINFO_DIRS=${rex}/share/terminfo:"
            # Go refuses to start under a GODEBUG naming a removed setting,
            # which some systems export to every session.
            "GODEBUG="
          ]
          # Rex's tsnet node sends from the same host as the tailnet relay, so
          # it disables UDP GSO for the same reason (packages/tailnet-relay).
          ++ lib.optional tailnetNode "TS_DEBUG_DISABLE_UDP_GSO=true";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
    })
  ];
}
