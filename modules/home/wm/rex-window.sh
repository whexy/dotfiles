# Rex windows under AeroSpace.
#
#   rex-window scratch   show the floating window of the session named
#                        scratch on the focused workspace, or put it away
#                        when it already has focus there
#   rex-window new       open a tiled Rex window on the focused workspace
#
# Rex's own Toggle Visibility brings the whole app forward, and AeroSpace then
# follows it to the workspace a Rex window sits on. These drive one window at a
# time through Rex's CLI instead, which reaches the app only while its Remote
# Control setting is on.

rex="/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
app_binary="/Applications/Rex Beta.app/Contents/MacOS/Rex"
bundle=com.superlogical.rex
session=scratch
# The scratch window waits here while put away; sketchybar draws only 1-9.
stash=scratch

windows() {
  aerospace list-windows --monitor all --app-bundle-id "$bundle" \
    --format '%{window-id}|%{workspace}|%{window-layout}|%{window-title}'
}

sessions() {
  "$rex" ls --json | jq -r '.sessions[].session_id' | sort
}

# Moves window $1 to workspace $2 as a $3 (floating or tiling) window and
# focuses it.
place() {
  local id=$1 workspace=$2 layout=$3 line current_workspace current_layout
  line=$(windows | grep "^$id|")
  IFS='|' read -r _ current_workspace current_layout _ <<<"$line"
  if [ "$current_workspace" != "$workspace" ]; then
    aerospace move-node-to-workspace --window-id "$id" "$workspace"
  fi
  if [ "$layout" = floating ] && [ "$current_layout" != floating ]; then
    aerospace layout --window-id "$id" floating
  elif [ "$layout" = tiling ] && [ "$current_layout" = floating ]; then
    aerospace layout --window-id "$id" tiling
  fi
  aerospace focus --window-id "$id"
}

# Opens a Rex window, which shows a session of its own, and prints the
# window's ID and that session's ID.
open_window() {
  local before_windows before_sessions id="" new_session=""
  before_windows=$(windows | cut -d'|' -f1 | sort)
  before_sessions=$(sessions)
  "$rex" "do" client.window.new >/dev/null
  for _ in $(seq 50); do
    id=$(comm -13 <(echo "$before_windows") <(windows | cut -d'|' -f1 | sort) | head -n 1)
    new_session=$(comm -13 <(echo "$before_sessions") <(sessions) | head -n 1)
    if [ -n "$id" ] && [ -n "$new_session" ]; then
      echo "$id $new_session"
      return
    fi
    sleep 0.1
  done
  echo "rex-window: Rex opened no window" >&2
  exit 1
}

scratch() {
  local workspace focused line id="" window_workspace title opened scratch_id
  workspace=$(aerospace list-workspaces --focused)
  focused=$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null || true)

  # Rex titles a window "<program> <directory> - <session label>".
  while IFS= read -r line; do
    title=${line#*|*|*|}
    if [[ $title == *" - $session" ]]; then
      id=${line%%|*}
      IFS='|' read -r _ window_workspace _ <<<"$line"
      break
    fi
  done < <(windows)

  if [ -n "$id" ] && [ "$id" = "$focused" ] && [ "$window_workspace" = "$workspace" ]; then
    aerospace move-node-to-workspace --window-id "$id" "$stash"
    return
  fi

  if [ -z "$id" ]; then
    scratch_id=$("$rex" ls --json | jq -r --arg label "$session" \
      'first(.sessions[] | select(.label == $label) | .session_id) // empty')
    opened=$(open_window)
    id=${opened%% *}
    if [ -n "$scratch_id" ]; then
      # The new window is the one Rex used last, so it switches to scratch,
      # and the session it came with is no longer shown anywhere.
      "$rex" "do" session.select session_id="$scratch_id" >/dev/null
      "$rex" kill "${opened#* }" >/dev/null
    else
      "$rex" session rename "${opened#* }" "$session" >/dev/null
    fi
  fi

  place "$id" "$workspace" floating
}

new() {
  local workspace opened
  workspace=$(aerospace list-workspaces --focused)
  opened=$(open_window)
  place "${opened%% *}" "$workspace" tiling
}

# The app opens its own window when it starts, on the focused workspace.
if ! /usr/bin/pgrep -qf "^$app_binary" 2>/dev/null; then
  /usr/bin/open -a 'Rex Beta'
  exit 0
fi

case ${1:-} in
scratch) scratch ;;
new) new ;;
*)
  echo "usage: rex-window scratch|new" >&2
  exit 2
  ;;
esac
