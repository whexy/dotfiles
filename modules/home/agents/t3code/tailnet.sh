route_matches() {
  timeout -k 1 3 tailscale serve status --json |
    jq -e --arg host "$name:$serve_port" --arg backend "$backend" \
      '.Web[$host].Handlers["/"].Proxy == $backend' >/dev/null
}

cleanup() {
  # An offline startup leaves T3 unaware of a route this helper later creates.
  # An explicit root path keeps other handlers on the same port intact.
  if [ -n "${name:-}" ] && route_matches; then
    timeout -k 1 3 tailscale serve --https="$serve_port" --set-path=/ off ||
      echo 't3-tailnet: could not remove its route' >&2
  fi
}
trap cleanup EXIT
trap 'exit 0' TERM INT

while true; do
  if status=$(timeout -k 2 10 tailscale status --json) &&
    current_name=$(jq -er 'select(.BackendState == "Running") | .Self.DNSName | select(type == "string" and length > 0) | rtrimstr(".")' <<<"$status"); then
    name=$current_name
    if ! route_matches; then
      timeout -k 2 10 tailscale serve --bg --https="$serve_port" "$backend" ||
        echo 't3-tailnet: route setup failed; retrying' >&2
    fi
  fi
  sleep 10
done
