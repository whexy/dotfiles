# The body of t3-mesh. mesh.nix defines t3, members, tailnet_url, public_url
# and alert_url above it.

# A link lasts 30 days. Renewing at two weeks left survives a missed weekly run.
renew_within=$((14 * 86400))
# The scopes a full-access link's pairing code must carry: mcpClientScopes
# in T3 Code's contracts.
link_scopes=(--scope orchestration:read --scope orchestration:operate
  --scope settings:write --scope source-control:write)

self=$(uname -n)
self=${self%%.*}
failures=()

fail() {
  echo "t3-mesh: $*" >&2
  failures+=("$*")
}

# Runs t3 on a member: directly here, else through a login shell there, which
# puts the Nix profile's t3 on PATH. No argument may need quoting.
on() {
  local host=$1
  shift
  if [ "$host" = "$self" ]; then
    timeout 120 "$t3" "$@"
  else
    timeout 120 ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" sh -lc "\"t3 $*\""
  fi
}

# Revokes the sessions on $2 that $1's older links to it left behind; $1
# keeps only the newest.
revoke_replaced() {
  local from=$1 to=$2 sessions id
  sessions=$(on "$to" auth session list --json) || return
  for id in $(jq -r --arg label "T3 Code · ${label[$from]}" '
    [.[] | select(.subject == "mcp-client" and .client.label == $label)]
    | sort_by(.issuedAt) | .[:-1][] | .sessionId' <<<"$sessions"); do
    on "$to" auth session revoke "$id" >/dev/null || return
  done
}

link() {
  local from=$1 to=$2 pairing code
  pairing=$(on "$to" auth pairing create --json --label "t3-mesh-$from" --ttl 5m "${link_scopes[@]}") ||
    return
  code=$(jq -r '.credential' <<<"$pairing")
  [[ $code =~ ^[A-Za-z0-9-]+$ ]] || return
  on "$from" environment link "${tailnet_url[$to]}" --url "${public_url[$to]}" \
    --access full-access --pairing-code "$code" >/dev/null || return
  revoke_replaced "$from" "$to" || echo "t3-mesh: $to kept $from's replaced sessions" >&2
  echo "t3-mesh: linked $from to $to"
}

declare -A env_id label
up=()
for host in "${members[@]}"; do
  if descriptor=$(curl -q -fsS --max-time 10 "${tailnet_url[$host]}/.well-known/t3/environment"); then
    env_id[$host]=$(jq -r '.environmentId' <<<"$descriptor")
    label[$host]=$(jq -r '.label' <<<"$descriptor")
    up+=("$host")
  else
    fail "no T3 Code server answers on $host"
  fi
done

now=$(date +%s)
for from in "${up[@]}"; do
  if ! links=$(on "$from" environment list --json); then
    fail "could not list $from's links"
    continue
  fi
  for to in "${up[@]}"; do
    [ "$from" != "$to" ] || continue
    expires=$(jq -r --arg id "${env_id[$to]}" \
      '.[] | select(.environmentId == $id) | .expiresAt' <<<"$links")
    if [ -n "$expires" ] && [ $(($(date -d "$expires" +%s) - now)) -gt "$renew_within" ]; then
      continue
    fi
    link "$from" "$to" || fail "could not link $from to $to"
  done
done

if [ ${#failures[@]} -gt 0 ]; then
  body=$(jq -n --arg source "t3-mesh/$self" \
    --arg title "T3 mesh on $self: ${#failures[@]} problem(s)" \
    --arg detail "$(printf '%s\n' "${failures[@]}")" --arg url "${tailnet_url[$self]:-}" \
    '{source: $source, severity: "warn", title: $title, detail: $detail, url: $url}')
  curl -q --silent --show-error --fail --output /dev/null --max-time 5 \
    --header 'content-type: application/json' --data "$body" "$alert_url" ||
    echo "t3-mesh: could not send the alert" >&2
  exit 1
fi
