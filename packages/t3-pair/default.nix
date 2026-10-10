{ pkgs }:

# Mints a T3 Code pairing URL for the server on a dev host, or on this machine
# when no host is given.
#
# The token is minted on the dev host (over ssh unless it is this machine) and
# handed back as a pairing URL on the host's Tailscale Serve name, which is
# where the client connects from then on. ssh and tailscale come from PATH on purpose: they must be the
# user's configured ssh and the CLI matching the running tailscaled.
pkgs.writeShellApplication {
  name = "t3-pair";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
    pkgs.jq
  ]
  ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.wl-clipboard;
  text = ''
    usage() {
      cat <<'EOF'
    usage: t3-pair [--label LABEL] [--ttl DURATION] [host]

    Mint a one-time T3 Code pairing URL on [host] (a tailnet machine name, or
    this machine when omitted) and copy it to the clipboard when one is
    available. Paste it into T3 Code under Settings -> Connections -> Add
    environment.

      --label LABEL     name shown in the host's client list (default: this host)
      --ttl DURATION    how long the unused link stays valid (default: 5m)
    EOF
    }

    label=$(hostname -s)
    ttl=5m
    host=""

    while [ $# -gt 0 ]; do
      case "$1" in
        --label)
          label="''${2:-}"
          shift 2
          ;;
        --ttl)
          ttl="''${2:-}"
          shift 2
          ;;
        -h | --help)
          usage
          exit 0
          ;;
        -*)
          usage >&2
          exit 2
          ;;
        *)
          host="$1"
          shift
          ;;
      esac
    done

    # Every value is spliced into a command run by two remote shells (the
    # login shell ssh picks, then sh), so restrict them instead of quoting.
    for value in ''${host:+"$host"} "$label" "$ttl"; do
      if ! [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "t3-pair: '$value' may only contain letters, digits, '.', '_' and '-'" >&2
        exit 2
      fi
    done

    if ! status=$(tailscale status --json 2>/dev/null) ||
      [ "$(jq -r '.BackendState' <<<"$status")" != Running ]; then
      echo "t3-pair: this machine is not connected to a tailnet" >&2
      exit 1
    fi
    # Match on the MagicDNS label rather than HostName: that is the name the
    # HTTPS certificate is issued for.
    peer=$(
      jq -r --arg host "''${host,,}" '
        if $host == "" then .Self
        else
          [.Self, (.Peer // {} | .[])]
          | map(select((.DNSName | split(".")[0]) == $host))
          | first // empty
        end
        | "\(.ID) \(.DNSName | rtrimstr("."))"
      ' <<<"$status"
    )
    if [ -z "$peer" ]; then
      echo "t3-pair: no tailnet machine named '$host'" >&2
      exit 1
    fi
    read -r peer_id dns_name <<<"$peer"

    base_url="https://$dns_name:35338"
    # Every agent host has the t3 CLI, which mints tokens whether or not a
    # server is running, so only a live server proves the URL will work.
    if ! curl -fs --max-time 10 -o /dev/null "$base_url/"; then
      echo "t3-pair: no T3 Code server answers at $base_url" >&2
      exit 1
    fi

    create=(t3 auth pairing create --json --label "$label" --ttl "$ttl" --base-url "$base_url")
    if [ "$peer_id" = "$(jq -r '.Self.ID' <<<"$status")" ]; then
      pairing=$("''${create[@]}")
    else
      # A login shell is what puts the Nix profiles on PATH for a
      # non-interactive ssh command.
      pairing=$(ssh "$host" sh -lc "\"''${create[*]}\"")
    fi

    url=$(jq -r '.pairUrl' <<<"$pairing")
    expires=$(jq -r '.expiresAt' <<<"$pairing")

    echo "$url"
    echo "Single use, expires $expires." >&2

    if [ "$(uname)" = Darwin ]; then
      printf '%s' "$url" | pbcopy
      echo "Copied to the clipboard." >&2
    elif [ -n "''${WAYLAND_DISPLAY:-}" ]; then
      printf '%s' "$url" | wl-copy
      echo "Copied to the clipboard." >&2
    fi
    echo "Paste it into T3 Code: Settings -> Connections -> Add environment." >&2
  '';
}
