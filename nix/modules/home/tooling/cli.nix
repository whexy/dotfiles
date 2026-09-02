# Everyday CLI tools: file/process inspection, decompressors, and general
# utilities. Shared by all development presets.
{
  config,
  pkgs,
  lib,
  inputs,
  perSystem,
  ...
}:
let
  # macOS ships caffeinate; Linux has no equivalent command, so rebuild it on
  # top of logind inhibitors. Tools are referenced by absolute store path so the
  # wrapper does not reorder PATH for the utility it runs.
  caffeinate = pkgs.writeShellApplication {
    name = "caffeinate";
    runtimeInputs = [ ];
    text = ''
      usage() {
        cat >&2 <<'EOF'
      usage: caffeinate [-dimsu] [-t timeout] [-w pid] [utility [argument ...]]

        -d  prevent the display from sleeping
        -i  prevent the system from sleeping when idle (default)
        -m  prevent the disk from idling (accepted, no logind equivalent)
        -s  prevent the system from sleeping at all
        -t  hold the assertions for <timeout> seconds
        -u  declare the user active
        -w  hold the assertions until <pid> exits

      With a utility, assertions are held until it exits; otherwise until -t or
      -w elapses, or until caffeinate is killed.
      EOF
      }

      display=0
      what=""
      timeout=""
      waitpid=""

      add_what() {
        case ":$what:" in
          *":$1:"*) ;;
          *) what="''${what:+$what:}$1" ;;
        esac
      }

      while getopts ':dimst:uw:h' opt; do
        case "$opt" in
          # Compositor idle inhibitors and logind inhibitors are independent, so -d
          # also asserts idle: a lit display on a suspended machine is not useful.
          d)
            display=1
            add_what idle
            ;;
          i | u) add_what idle ;;
          m) ;;
          s) add_what sleep ;;
          t) timeout=$OPTARG ;;
          w) waitpid=$OPTARG ;;
          h)
            usage
            exit 0
            ;;
          :)
            echo "caffeinate: option requires an argument -- $OPTARG" >&2
            exit 2
            ;;
          *)
            echo "caffeinate: illegal option -- $OPTARG" >&2
            usage
            exit 2
            ;;
        esac
      done
      shift $((OPTIND - 1))

      [ -n "$what" ] || what=idle

      if [ "$display" = 1 ] && [ -z "''${WAYLAND_DISPLAY:-}" ]; then
        echo "caffeinate: -d needs a Wayland session; keeping the system awake only" >&2
        display=0
      fi

      if [ "$#" -gt 0 ]; then
        why="caffeinate $1"
      elif [ -n "$waitpid" ]; then
        why="caffeinate -w $waitpid"
        set -- ${pkgs.coreutils}/bin/tail --pid="$waitpid" -f /dev/null
      elif [ -n "$timeout" ]; then
        why="caffeinate -t $timeout"
        set -- ${pkgs.coreutils}/bin/sleep "$timeout"
      else
        why="caffeinate"
        set -- ${pkgs.coreutils}/bin/sleep infinity
      fi

      set -- ${pkgs.systemd}/bin/systemd-inhibit \
        --what="$what" \
        --who=caffeinate \
        --why="$why" \
        --mode=block \
        -- "$@"

      # Without -d there is nothing to clean up, so become systemd-inhibit:
      # killing caffeinate then drops the lock instead of orphaning the holder.
      if [ "$display" = 0 ]; then
        exec "$@"
      fi

      ${pkgs.wlinhibit}/bin/wlinhibit &
      wlinhibit_pid=$!

      "$@" &
      inhibit_pid=$!
      trap 'kill "$inhibit_pid" 2>/dev/null || true' INT TERM HUP

      set +e
      wait "$inhibit_pid"
      status=$?
      # A trapped signal makes wait return early; reap the real status.
      if [ "$status" -gt 128 ]; then
        wait "$inhibit_pid"
        status=$?
      fi
      set -e

      kill "$wlinhibit_pid" 2>/dev/null || true
      exit "$status"
    '';
  };
in
{
  config = lib.mkIf config.dotfiles.tooling.cli.enable {
    home.packages =
      with pkgs;
      [
        age
        inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.agenix
        bzip2
        cloudflared
        duf
        dust
        fd
        file
        just
        kubectl
        lazygit
        lldb
        lsof
        ncdu
        nix-output-monitor
        p7zip
        perSystem.self.doordash-cli
        ripgrep
        tldr
        unrar
        xz
      ]
      ++ lib.optionals config.targets.genericLinux.enable [
        _1password-cli
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        caffeinate
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        # only available on macOS
        container
      ];
  };
}
