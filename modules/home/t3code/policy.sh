# The preamble from policy.nix sets t3, no_policy, policy_url, alert_url
# and editor_url.

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/t3code-policy
last_good=$state_dir/policy.json
status_file=$state_dir/status.json

log() { printf 't3code-policy: %s\n' "$*" >&2; }

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Validates a policy with the server binary about to run; on failure, sets
# check_error to the first line of its complaint.
check() {
  local output
  # T3 logs the complaint to stdout, after a "[time] ERROR (#n): " prefix.
  if output=$("$t3" policy check "$1" 2>&1); then
    return 0
  fi
  check_error=${output%%$'\n'*}
  check_error=${check_error#\[*\] ERROR \(#*\): }
  check_error=${check_error:0:300}
  return 1
}

# Fetches the policy into $candidate within an overall 30 s deadline, which
# also covers a boot that starts the server before Tailscale is up. Sets
# http_status, and fetch_error unless it succeeds.
fetch() {
  local deadline=$((SECONDS + 30)) delay=1 remaining code errors
  errors=$(mktemp "$state_dir/.curl.XXXXXX")
  while :; do
    remaining=$((deadline - SECONDS))
    if [ "$remaining" -le 0 ]; then
      break
    fi
    if code=$(curl -q --silent --show-error --max-time "$remaining" --connect-timeout "$((remaining < 10 ? remaining : 10))" \
      --output "$candidate" --write-out '%{http_code}' "$policy_url" 2>"$errors"); then
      http_status=$code
      if [ "$code" = 200 ]; then
        rm -f "$errors"
        return 0
      fi
      fetch_error="HTTP $code"
      # Only a server error or a rate limit can change by asking again.
      case $code in
      5* | 429) ;;
      *) break ;;
      esac
    else
      # No response this time, so an earlier attempt's status no longer applies.
      http_status=
      fetch_error=$(head -n 1 "$errors")
    fi
    remaining=$((deadline - SECONDS))
    sleep "$((delay < remaining ? delay : (remaining > 0 ? remaining : 0)))"
    delay=$((delay * 2))
  done
  rm -f "$errors"
  return 1
}

notify() {
  local severity host body
  case $state in
  current) severity=ok ;;
  none) severity=error ;;
  *) severity=warn ;;
  esac
  host=$(uname -n)
  host=${host%%.*}
  body=$(jq -n --arg source "t3code-policy/$host" --arg severity "$severity" \
    --arg title "T3 policy on $(id -un)@$host: $state" \
    --arg detail "${error:-applied ${sha:0:12}}" --arg url "$editor_url" \
    '{source: $source, severity: $severity, title: $title, detail: $detail, url: $url}')
  curl -q --silent --show-error --fail --output /dev/null --max-time 5 \
    --header 'content-type: application/json' --data "$body" "$alert_url" ||
    log "could not send the $state alert"
}

resolve() {
  local previous last_success candidate http_status="" fetch_error="" check_error="" error="" state=none applied sha="" fresh_invalid=""
  mkdir -p "$state_dir"
  previous=$(jq -r '.state // ""' "$status_file" 2>/dev/null) || previous=
  last_success=$(jq -r '.last_success_at // ""' "$status_file" 2>/dev/null) || last_success=
  candidate=$(mktemp "$state_dir/.candidate.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -f '$candidate'" EXIT

  if fetch; then
    if check "$candidate"; then
      chmod 644 "$candidate"
      mv -f "$candidate" "$last_good"
      state=current
      last_success=$(now)
    else
      fresh_invalid=1
      error="invalid: $check_error"
    fi
  else
    error="unreachable: $fetch_error"
  fi

  if [ "$state" = none ] && [ -e "$last_good" ]; then
    if check "$last_good"; then
      state=$([ -n "$fresh_invalid" ] && echo stale-invalid || echo stale-unreachable)
    else
      mv -f "$last_good" "$last_good.rejected"
      error="$error; last good rejected: $check_error"
    fi
  fi

  if [ "$state" = none ]; then
    applied=$no_policy
  else
    applied=$last_good
    sha=$(sha256sum "$last_good")
    sha=${sha%% *}
  fi

  jq -n --arg state "$state" --arg sha "$sha" --arg last_success "$last_success" \
    --arg http "$http_status" --arg error "$error" --arg version "$("$t3" --version 2>/dev/null)" --arg at "$(now)" \
    'def blank: if . == "" then null else . end;
     {state: $state, applied_sha256: ($sha | blank), last_success_at: ($last_success | blank),
      http_status: ($http | tonumber? // null | if . == 0 then null else . end), error: ($error | blank),
      checked_with: ($version | blank), checked_at: $at}' >"$status_file.new"
  mv -f "$status_file.new" "$status_file"

  log "state=$state sha=${sha:0:12} http=${http_status:-none} err=${error:-none}"

  # The first start reports anything short of current; later ones report changes.
  if [ "$state" != "${previous:-current}" ]; then
    notify
  fi

  printf '%s\n' "$applied"
}

status() {
  local state applied
  if [ ! -e "$status_file" ]; then
    echo "No status yet: the T3 Code server has not started with a fetched policy."
    return 0
  fi
  jq . "$status_file"
  echo
  state=$(jq -r .state "$status_file")
  # What the wrapper exported at that start, so this shows what the server loads.
  applied=$([ "$state" = none ] && echo "$no_policy" || echo "$last_good")
  T3CODE_DEV_MANAGED_POLICY_PATH=$applied "$t3" policy show
}

case ${1:-} in
resolve) resolve ;;
status) status ;;
*)
  echo "usage: t3code-policy status" >&2
  echo "  resolve  fetch and check the policy, print the path to load (the server's wrapper runs it)" >&2
  exit 2
  ;;
esac
