{ pkgs, ... }:
let
  inherit (pkgs) lib coreutils gnused;

  # Each default-route lookup answers the next line of $ROUTES, "-" meaning no
  # route, and fails once they run out. After the first address the server is
  # starting, so later lookups wait until the fake t3 has logged its
  # arguments, which makes every scenario independent of timing.
  ip = pkgs.writeShellScriptBin "ip" ''
    [ "$*" = "-4 -j route get 1.1.1.1" ] || { echo "unexpected: ip $*" >&2; exit 99; }
    if [ -e "$ROUTES.started" ]; then
      until [ -s "$T3_LOG" ]; do ${coreutils}/bin/sleep 0.05; done
    fi
    answer=$(${coreutils}/bin/head -n 1 "$ROUTES")
    if [ -z "$answer" ]; then
      echo "routes exhausted" >&2
      exit 2
    fi
    ${gnused}/bin/sed -i 1d "$ROUTES"
    if [ "$answer" = - ]; then
      echo "RTNETLINK answers: Network is unreachable" >&2
      exit 2
    fi
    ${coreutils}/bin/touch "$ROUTES.started"
    echo "[{\"dst\":\"1.1.1.1\",\"dev\":\"eth0\",\"prefsrc\":\"$answer\"}]"
  '';

  # Logs its arguments once its TERM handler is in place, then runs until
  # terminated, or exits with $T3_EXIT.
  t3 = pkgs.writeShellScriptBin "t3" ''
    trap 'kill "$child" 2>/dev/null; echo terminated >>"$T3_LOG"; exit 143' TERM
    echo "$*" >>"$T3_LOG"
    if [ -n "''${T3_EXIT:-}" ]; then
      exit "$T3_EXIT"
    fi
    ${coreutils}/bin/sleep 1000 &
    child=$!
    wait "$child"
  '';

  # The serve script puts the profile first on PATH, so its 10 s polls take
  # no time here.
  profile = pkgs.symlinkJoin {
    name = "t3code-lan-profile";
    paths = [
      (pkgs.writeShellScriptBin "sleep" "exec ${coreutils}/bin/sleep 0.01")
      (pkgs.writeTextDir "etc/profile.d/hm-session-vars.sh" "")
    ];
  };

  serveWith =
    server:
    (import ../modules/home/agents/t3code/home.nix {
      inherit pkgs lib;
      config = {
        dotfiles.agents.t3code = {
          package = t3;
          server = {
            enable = true;
            network = "lan";
            lanInterface = null;
          }
          // server;
          pair.enable = false;
        };
        home = {
          profileDirectory = "${profile}";
          homeDirectory = "${profile}";
        };
      };
      perSystem.self.lan-address = import ../packages/lan-address/default.nix {
        pkgs = pkgs // {
          iproute2 = ip;
        };
      };
      gitConfig = "/dev/null";
    }).systemdUserServices.t3code.Service.ExecStart;
in
pkgs.runCommand "t3code-lan-test"
  {
    nativeBuildInputs = [ coreutils ];
    meta.platforms = lib.platforms.linux;
  }
  ''
    fail=0
    check() {
      if ! eval "$1"; then
        echo "FAIL: $2"
        fail=1
      fi
    }
    # serve <route answers...>
    serve() {
      work=$(mktemp -d)
      export ROUTES=$work/routes T3_LOG=$work/t3.log
      printf '%s\n' "$@" >"$ROUTES"
      status=0
      timeout 30 ${serveWith { }} >"$work/out" 2>&1 || status=$?
    }

    # No address at boot, a brief loss, and a one-off different address keep
    # the server on its address; a different address seen twice in a row
    # restarts it.
    serve - - 192.168.2.200 192.168.2.200 - 192.168.2.200 10.0.0.5 192.168.2.200 10.0.0.5 10.0.0.5
    check '[ "$status" = 1 ]' "move: exit status $status, want 1"
    check '[ ! -s "$ROUTES" ]' "move: restarted before the last answer: $(cat "$ROUTES")"
    check '[ "$(cat "$T3_LOG")" = "serve --host 192.168.2.200 --port 3773 --no-browser
    terminated" ]' "move: t3 log: $(cat "$T3_LOG")"
    check '[ "$(grep -c "no private LAN IPv4 address yet" "$work/out")" = 1 ]' "move: waiting logged other than once"
    check 'grep -q "moved from 192.168.2.200 to 10.0.0.5" "$work/out"' "move: no restart message"

    # A server that dies takes the service down with its status.
    T3_EXIT=3 serve 192.168.2.200
    check '[ "$status" = 3 ]' "crash: exit status $status, want 3"
    check '[ "$(cat "$T3_LOG")" = "serve --host 192.168.2.200 --port 3773 --no-browser" ]' "crash: t3 log: $(cat "$T3_LOG")"

    check 'grep -q -- "/bin/lan-address --interface eth1 " ${serveWith { lanInterface = "eth1"; }}' \
      "lanInterface does not reach lan-address"

    [ "$fail" = 0 ]
    touch $out
  ''
