{ pkgs }:

# Prints this host's private IPv4 LAN address, for services that must listen
# on the LAN and nowhere else.
#
# By default it takes the source address the kernel picks for the default
# route, which is the address LAN peers see. Taking any private address would
# also match bridges such as docker0's 172.17.0.1. Only RFC 1918 addresses
# qualify, so a public address, Tailscale's 100.64.0.0/10, or a link-local
# address never does. A host whose default route uses one of those needs
# --interface.
pkgs.writeShellApplication {
  name = "lan-address";
  runtimeInputs = [
    pkgs.iproute2
    pkgs.jq
  ];
  text = ''
    usage() {
      cat <<'EOF'
    usage: lan-address [--interface IFACE]

    Print this host's private IPv4 LAN address, or exit 1 when it has none.

      --interface IFACE   take the address on IFACE instead of the one the
                          default route uses
    EOF
    }

    interface=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --interface)
          [ $# -ge 2 ] || { usage >&2; exit 2; }
          interface="$2"
          shift 2
          ;;
        -h | --help)
          usage
          exit 0
          ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    done

    if [ -n "$interface" ]; then
      if ! info=$(ip -4 -j address show dev "$interface" scope global 2>/dev/null); then
        echo "lan-address: no interface named '$interface'" >&2
        exit 1
      fi
      candidates='.[].addr_info[].local'
      where="on $interface"
    else
      # Only asks the kernel which route it would use; nothing is sent.
      if ! info=$(ip -4 -j route get 1.1.1.1 2>/dev/null); then
        echo "lan-address: no default route" >&2
        exit 1
      fi
      candidates='.[].prefsrc'
      where="on the default route"
    fi

    # shellcheck disable=SC2016 # jq variables, not shell ones
    private='
      (split(".") | map(tonumber)) as [$a, $b]
      | $a == 10 or ($a == 172 and $b >= 16 and $b <= 31) or ($a == 192 and $b == 168)
    '
    address=$(jq -r "[$candidates | strings | select($private)] | first // empty" <<<"$info")
    if [ -z "$address" ]; then
      echo "lan-address: no private IPv4 address $where" >&2
      exit 1
    fi
    echo "$address"
  '';

  meta = {
    description = "Print this host's private IPv4 LAN address";
    mainProgram = "lan-address";
    platforms = pkgs.lib.platforms.linux;
  };
}
