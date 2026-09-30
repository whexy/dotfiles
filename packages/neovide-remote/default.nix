{ pkgs }:

# Opens a folder on an ssh host in a local Neovide, and handles the
# `vscode://vscode-remote/ssh-remote+<host>/<path>` links that tools emit for
# "open in editor" so they land in Neovide instead of VS Code.
#
# The remote Neovim runs headless and detached, keyed by host and folder, so a
# later link to the same folder reattaches to the running session. The UI talks
# to it through an ssh-forwarded Unix socket, which keeps the RPC endpoint (and
# the code execution it grants) private to the remote user.
let
  inherit (pkgs) lib;

  # Runs on the remote host under `sh -s`, so it works whatever the login shell
  # is. Prints the server socket once Neovim is listening on it.
  remoteScript = ''
    set -eu
    if [ -d "$target" ]; then
      dir=$target
      file=
    else
      dir=$(dirname -- "$target")
      file=$target
    fi
    cd "$dir"
    sock="''${XDG_RUNTIME_DIR:-''${TMPDIR:-/tmp}}/neovide-remote-$id.sock"
    if ! nvim --server "$sock" --remote-expr 1 >/dev/null 2>&1; then
      rm -f "$sock"
      umask 077
      if command -v setsid >/dev/null 2>&1; then
        setsid nvim --headless --listen "$sock" ''${file:+"$file"} </dev/null >/dev/null 2>&1 &
      else
        nohup nvim --headless --listen "$sock" ''${file:+"$file"} </dev/null >/dev/null 2>&1 &
      fi
      tries=0
      until [ -S "$sock" ]; do
        tries=$((tries + 1))
        if [ "$tries" -gt 100 ]; then
          echo "nvim did not start listening on $sock" >&2
          exit 1
        fi
        sleep 0.1
      done
    elif [ -n "$file" ]; then
      nvim --server "$sock" --remote "$file"
    fi
    printf '%s\n' "$sock"
  '';

  script = pkgs.writeShellApplication {
    name = "neovide-remote";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.neovide
      pkgs.openssh
    ]
    ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.libnotify;
    text = ''
      usage() {
        cat <<'EOF'
      usage: neovide-remote HOST PATH
             neovide-remote vscode://vscode-remote/ssh-remote+HOST/PATH
             neovide-remote vscode://file/PATH

      Start (or reuse) a headless Neovim in PATH on HOST and attach a local
      Neovide to it over an ssh-forwarded socket.
      EOF
      }

      # Launched from a URL click there is no terminal to read stderr.
      fail() {
        echo "neovide-remote: $1" >&2
        ${
          if pkgs.stdenv.hostPlatform.isDarwin then
            ''/usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Neovide Remote"' -e 'end run' "$1" || true''
          else
            ''notify-send --app-name "Neovide Remote" "Neovide Remote" "$1" || true''
        }
        exit 1
      }

      urldecode() {
        printf '%b' "''${1//%/\\x}"
      }

      case "''${1:-}" in
        -h | --help)
          usage
          exit 0
          ;;
        vscode://vscode-remote/*)
          rest=$(urldecode "''${1#vscode://vscode-remote/}")
          authority=''${rest%%/*}
          path=/''${rest#*/}
          [[ $authority == ssh-remote+* ]] || fail "unsupported remote: $authority"
          host=''${authority#ssh-remote+}
          ;;
        vscode://file/*)
          exec neovide --no-fork "$(urldecode "''${1#vscode://file}")"
          ;;
        *)
          [ $# -eq 2 ] || {
            usage >&2
            exit 2
          }
          host=$1
          path=$2
          ;;
      esac
      [ -n "$host" ] || fail "no host in $1"

      id=$(printf '%s\n' "$(id -un)@$(uname -n):$host:$path" | sha256sum | cut -c1-16)
      quote() { printf "'%s'" "''${1//\'/\'\\\'\'}"; }

      # Any web page can emit these links, so no host is handed the agent. The
      # remote end only drives the UI, so host keys are learned on first use:
      # there is no terminal to confirm them. A changed key still fails, and
      # has to, since ssh would otherwise drop the socket forward.
      ssh_opts=(-o ForwardAgent=no -o StrictHostKeyChecking=accept-new)

      remote_sock=$(
        {
          printf 'target=%s\nid=%s\n' "$(quote "$path")" "$id"
          cat <<'EOF'
      ${remoteScript}
      EOF
        } | ssh -T "''${ssh_opts[@]}" "$host" sh -s 2>&1
      ) || fail "could not start nvim on $host: $remote_sock"
      remote_sock=''${remote_sock##*$'\n'}

      rundir="''${XDG_RUNTIME_DIR:-''${TMPDIR:-/tmp}}/neovide-remote"
      [ -d "$rundir" ] || mkdir -m 700 "$rundir"
      local_sock="$rundir/$id.sock"

      # A dedicated connection, not a multiplexed one: forwards requested
      # through a ControlMaster outlive this process and pin the socket path.
      ssh -N -T "''${ssh_opts[@]}" \
        -o ControlPath=none \
        -o ExitOnForwardFailure=yes \
        -o StreamLocalBindUnlink=yes \
        -L "$local_sock:$remote_sock" \
        "$host" &
      tunnel=$!
      trap 'kill "$tunnel" 2>/dev/null || true; rm -f "$local_sock"' EXIT

      tries=0
      until [ -S "$local_sock" ]; do
        kill -0 "$tunnel" 2>/dev/null || fail "ssh tunnel to $host exited"
        tries=$((tries + 1))
        # Generous: the first connection may wait on an agent approval prompt.
        [ "$tries" -le 600 ] || fail "timed out forwarding $remote_sock from $host"
        sleep 0.1
      done

      neovide --no-fork --server "$local_sock"
    '';
  };

  # LaunchServices delivers URLs as Apple Events rather than argv, so macOS
  # needs a bundle that receives them and hands each to the script.
  darwinApp = pkgs.stdenv.mkDerivation {
    pname = "neovide-remote-app";
    version = "0.1.0";
    src = ./handler.m;
    dontUnpack = true;
    buildPhase = ''
      runHook preBuild
      $CC -fobjc-arc -Wall -Wextra -Werror -O2 -framework Cocoa \
        -DSCRIPT='"${lib.getExe script}"' "$src" -o neovide-remote-handler
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      app="$out/Applications/Neovide Remote.app/Contents"
      install -Dm755 neovide-remote-handler "$app/MacOS/neovide-remote-handler"
      install -Dm644 ${./Info.plist} "$app/Info.plist"
      runHook postInstall
    '';
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "neovide-remote";
    desktopName = "Neovide Remote";
    comment = "Open vscode:// remote links in Neovide";
    exec = "${lib.getExe script} %u";
    icon = "neovide";
    noDisplay = true;
    mimeTypes = [ "x-scheme-handler/vscode" ];
  };
in
pkgs.symlinkJoin {
  name = "neovide-remote";
  paths = [
    script
  ]
  ++ (if pkgs.stdenv.hostPlatform.isDarwin then [ darwinApp ] else [ desktopItem ]);
  meta = {
    description = "Open folders on ssh hosts, and vscode:// remote links, in Neovide";
    mainProgram = "neovide-remote";
    platforms = lib.platforms.unix;
  };
}
