# The preamble from policy-command.nix sets t3, no_policy, policy_url,
# alert_url and editor_url, and defines server_running and restart_server.

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/t3code-policy
last_good=$state_dir/policy.json
status_file=$state_dir/status.json
lock_wait=${T3CODE_POLICY_LOCK_WAIT:-60}
check_timeout=20

log() { printf 't3code-policy: %s\n' "$*" >&2; }

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# The wrapper's resolve and the updater both rewrite status.json, and the
# updater must not judge the applied policy while a start is replacing it.
lock() {
  exec 9>"$state_dir/.lock"
  flock "$@" 9
}

# Applies a jq filter to status.json, starting from {} when it is missing.
write_status() {
  local current
  current=$(jq -c . "$status_file" 2>/dev/null) || current=
  printf '%s\n' "${current:-"{}"}" | jq "$@" >"$status_file.new"
  mv -f "$status_file.new" "$status_file"
}

# Validates a policy with the server binary about to run; on failure, sets
# check_error to the first line of its complaint, and check_status to 124 on
# a timeout.
check() {
  local output
  check_status=0
  # T3 logs the complaint to stdout, after a "[time] ERROR (#n): " prefix.
  output=$(timeout "$check_timeout" "$t3" policy check "$1" 2>&1) || check_status=$?
  if [ "$check_status" = 0 ]; then
    return 0
  elif [ "$check_status" = 124 ]; then
    check_error="t3 policy check timed out after ${check_timeout}s"
    return 1
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
  local previous last_success candidate http_status="" fetch_error="" check_error="" error="" state=none applied sha="" stale=unreachable
  mkdir -p "$state_dir"
  # The updater is bounded well below this wait, so a held lock means
  # something is stuck; start on the last good copy and leave state alone.
  if ! lock -w "$lock_wait"; then
    applied=$no_policy
    if [ -e "$last_good" ] && check "$last_good"; then
      applied=$last_good
      sha=$(sha256sum "$last_good")
      sha=${sha%% *}
    fi
    log "state=locked sha=${sha:0:12} http=none err=status.json is locked; loaded the last good copy without updating it"
    printf '%s\n' "$applied"
    return 0
  fi
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
      stale=invalid
      error="invalid: $check_error"
    fi
  else
    case $http_status in
    404 | 410)
      stale=missing
      error="missing: $fetch_error"
      ;;
    *) error="unreachable: $fetch_error" ;;
    esac
  fi

  if [ "$state" = none ] && [ -e "$last_good" ]; then
    if check "$last_good"; then
      state=stale-$stale
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

  # shellcheck disable=SC2016 # a jq program
  write_status --arg state "$state" --arg sha "$sha" --arg last_success "$last_success" \
    --arg http "$http_status" --arg error "$error" --arg version "$("$t3" --version 2>/dev/null)" --arg at "$(now)" \
    'def blank: if . == "" then null else . end;
     {state: $state, applied_sha256: ($sha | blank), last_success_at: ($last_success | blank),
      http_status: ($http | tonumber? // null | if . == 0 then null else . end), error: ($error | blank),
      checked_with: ($version | blank), checked_at: $at}
     + (if .update then {update} else {} end)'

  log "state=$state sha=${sha:0:12} http=${http_status:-none} err=${error:-none}"

  # The first start reports anything short of current; later ones report changes.
  if [ "$state" != "${previous:-current}" ]; then
    notify
  fi

  printf '%s\n' "$applied"
}

# Reads one field of status.json, or nothing.
status_field() { jq -r "($1) // \"\"" "$status_file" 2>/dev/null || true; }

# Restarts the running server when the policy at policy_url differs from the
# one it applied; the wrapper then fetches and applies it at start. A sha the
# last restart was for, which the server still does not apply (its start fell
# back to the last good copy), gets no second restart within retry_after.
# Every step is bounded, about 50 s in all, below the wrapper's lock wait.
update() {
  local retry_after=3600 applied state previous_result previous_sha previous_error restarted_for restarted_at
  local candidate errors code="" headers=() result sha="" http_status="" error="" check_error="" check_status=0 new_state
  mkdir -p "$state_dir"
  # A start is resolving, or the previous run has not finished.
  lock -n || return 0
  applied=$(status_field .applied_sha256)
  state=$(status_field .state)
  previous_result=$(status_field .update.result)
  previous_sha=$(status_field .update.sha256)
  previous_error=$(status_field .update.error)
  restarted_for=$(status_field .update.restarted_for)
  restarted_at=$(status_field '.update.restarted_at | fromdateiso8601?')

  if ! server_running; then
    result=server-stopped
  else
    candidate=$(mktemp "$state_dir/.candidate.XXXXXX")
    errors=$(mktemp "$state_dir/.curl.XXXXXX")
    # shellcheck disable=SC2064
    trap "rm -f '$candidate' '$errors'" EXIT
    if [ -n "$applied" ]; then
      headers=(--header "If-None-Match: \"$applied\"")
    fi
    if code=$(curl -q --silent --show-error --max-time 10 --connect-timeout 5 "${headers[@]}" \
      --output "$candidate" --write-out '%{http_code}' "$policy_url" 2>"$errors"); then
      http_status=$code
    else
      error=$(head -n 1 "$errors")
    fi
    case $http_status in
    304)
      result=unchanged
      sha=$applied
      ;;
    200)
      sha=$(sha256sum "$candidate")
      sha=${sha%% *}
      if [ "$sha" = "$applied" ]; then
        result=unchanged
      elif [ "$sha" = "$previous_sha" ] && [ "$previous_result" = invalid ]; then
        # The same bytes get the same verdict; a start checks them again.
        result=invalid
        error=$previous_error
      elif ! check "$candidate" && [ "$check_status" = 124 ]; then
        result=check-timeout
        error=$check_error
      elif [ "$check_status" != 0 ]; then
        result=invalid
        error="invalid: $check_error"
      elif [ "$sha" = "$restarted_for" ] && [ $(($(date +%s) - ${restarted_at:-0})) -lt "$retry_after" ]; then
        result=backoff
        error="still applying ${applied:0:12} after the restart for it"
      elif ! server_running; then
        # Stopped while this run fetched; a restart would start it again.
        result=server-stopped
      elif restart_server; then
        result=restarted
        restarted_for=$sha
        restarted_at=$(date +%s)
      else
        result=restart-failed
        error="could not restart the server"
      fi
      ;;
    404 | 410) result=missing error="missing: HTTP $http_status" ;;
    "") result=unreachable error="unreachable: $error" ;;
    *) result=unreachable error="unreachable: HTTP $http_status" ;;
    esac
  fi

  # The served policy now matches the applied one, or is invalid or gone.
  new_state=$state
  case $result:$state in
  unchanged:stale-*) new_state=current ;;
  invalid:current | invalid:stale-*) new_state="stale-invalid" ;;
  missing:current | missing:stale-*) new_state="stale-missing" ;;
  esac

  # shellcheck disable=SC2016 # a jq program
  write_status --arg state "$new_state" --arg previous "$state" --arg at "$(now)" --arg result "$result" \
    --arg sha "$sha" --arg http "$http_status" --arg error "$error" \
    --arg restarted_for "$restarted_for" --arg restarted_at "$restarted_at" \
    'def blank: if . == "" then null else . end;
     (if $state == $previous then .
      elif $state == "current" then .state = $state | .error = null | .last_success_at = $at
      else .state = $state | .error = $error end)
     | .update = {checked_at: $at, result: $result, sha256: ($sha | blank),
                  http_status: ($http | tonumber? // null), error: ($error | blank),
                  restarted_for: ($restarted_for | blank),
                  restarted_at: (if $restarted_at == "" then null else $restarted_at | tonumber | todateiso8601 end)}'

  if [ "$result" != "$previous_result" ] || [ "$sha" != "$previous_sha" ] || [ "$result" = restarted ]; then
    log "update=$result sha=${sha:0:12} http=${http_status:-none} err=${error:-none}"
  fi

  if [ "$new_state" != "$state" ]; then
    state=$new_state
    if [ "$state" = current ]; then
      error=
    fi
    notify
  fi
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
update) update ;;
status) status ;;
*)
  echo "usage: t3code-policy status" >&2
  echo "  resolve  fetch and check the policy, print the path to load (the server's wrapper runs it)" >&2
  echo "  update   restart the running server if the policy changed (its timer runs it)" >&2
  exit 2
  ;;
esac
