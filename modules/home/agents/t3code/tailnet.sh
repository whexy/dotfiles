while true; do
  if status=$(timeout -k 2 10 tailscale status --json) &&
    name=$(jq -er 'select(.BackendState == "Running") | .Self.DNSName | select(type == "string" and length > 0) | rtrimstr(".")' <<<"$status"); then
    if ! timeout -k 2 10 tailscale serve status --json |
      jq -e --arg host "$name:35338" \
        '.Web[$host].Handlers["/"].Proxy == "http://127.0.0.1:3773"' >/dev/null; then
      timeout -k 2 10 tailscale serve --bg --https=35338 http://127.0.0.1:3773 ||
        echo 't3-tailnet: route setup failed; retrying' >&2
    fi
  fi
  sleep 10
done
