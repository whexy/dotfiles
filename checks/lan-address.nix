{ pkgs, ... }:
let
  # Answers like iproute2 on a host with a LAN, a Docker bridge, Tailscale, a
  # public uplink, and a link-local fallback. FAKE_ROUTE is the default
  # route's source address; unset means there is no default route.
  interfaces = builtins.toJSON [
    {
      ifname = "eth0";
      addr_info = [
        { local = "192.168.2.200"; }
        { local = "192.168.2.201"; }
      ];
    }
    {
      ifname = "eth1";
      addr_info = [
        { local = "169.254.3.3"; }
        { local = "10.0.0.5"; }
      ];
    }
    {
      ifname = "docker0";
      addr_info = [ { local = "172.17.0.1"; } ];
    }
    {
      ifname = "tailscale0";
      addr_info = [ { local = "100.100.1.2"; } ];
    }
    {
      ifname = "wan0";
      addr_info = [ { local = "203.0.113.7"; } ];
    }
  ];
  ip = pkgs.writeShellScriptBin "ip" ''
    case "$*" in
      "-4 -j route get 1.1.1.1")
        if [ -z "''${FAKE_ROUTE:-}" ]; then
          echo "RTNETLINK answers: Network is unreachable" >&2
          exit 2
        fi
        echo "[{\"dst\":\"1.1.1.1\",\"dev\":\"eth0\",\"prefsrc\":\"$FAKE_ROUTE\"}]"
        ;;
      "-4 -j address show dev "*" scope global")
        found=$(${pkgs.jq}/bin/jq -c --arg dev "$6" 'map(select(.ifname == $dev))' <<'EOF'
    ${interfaces}
    EOF
        )
        if [ "$found" = "[]" ]; then
          echo "Device \"$6\" does not exist." >&2
          exit 1
        fi
        echo "$found"
        ;;
      *)
        echo "unexpected: ip $*" >&2
        exit 99
        ;;
    esac
  '';
  package = import ../packages/lan-address/default.nix {
    pkgs = pkgs // {
      iproute2 = ip;
    };
  };
in
pkgs.runCommand "lan-address-test"
  {
    meta.platforms = pkgs.lib.platforms.linux;
  }
  ''
    fail=0
    # expect <status> <output> [FAKE_ROUTE] -- [args...]
    expect() {
      local want_status=$1 want_output=$2 route=$3
      shift 4
      local output status=0
      output=$(FAKE_ROUTE=$route ${package}/bin/lan-address "$@" 2>/dev/null) || status=$?
      if [ "$status" != "$want_status" ] || [ "$output" != "$want_output" ]; then
        echo "FAIL: route='$route' args='$*': got $status '$output', want $want_status '$want_output'"
        fail=1
      fi
    }

    # The default route's address wins over every other private address.
    expect 0 192.168.2.200 192.168.2.200 --
    expect 0 10.0.0.5 10.0.0.5 --
    # A public, Tailscale, or link-local default route has no LAN address,
    # and nothing falls back to another interface such as docker0.
    expect 1 "" 203.0.113.7 --
    expect 1 "" 100.100.1.2 --
    expect 1 "" 169.254.3.3 --
    expect 1 "" "" --
    # RFC 1918 boundaries.
    expect 0 172.16.0.1 172.16.0.1 --
    expect 0 172.31.255.254 172.31.255.254 --
    expect 1 "" 172.15.255.254 --
    expect 1 "" 172.32.0.1 --
    expect 1 "" 192.169.0.1 --
    expect 1 "" 11.0.0.1 --
    # A pinned interface ignores the default route, takes its first private
    # address, and never borrows one from another interface.
    expect 0 192.168.2.200 203.0.113.7 -- --interface eth0
    expect 0 10.0.0.5 "" -- --interface eth1
    expect 0 172.17.0.1 192.168.2.200 -- --interface docker0
    expect 1 "" 192.168.2.200 -- --interface wan0
    expect 1 "" 192.168.2.200 -- --interface tailscale0
    expect 1 "" 192.168.2.200 -- --interface missing
    expect 2 "" 192.168.2.200 -- --interface
    expect 2 "" 192.168.2.200 -- extra

    [ "$fail" = 0 ]
    touch $out
  ''
