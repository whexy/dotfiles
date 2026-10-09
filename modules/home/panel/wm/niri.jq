# Fold `niri msg --json event-stream` into the state that
# `niri msg --json workspaces` and `niri msg --json focused-window` report.
#
#   niri msg --json event-stream | jq -n --unbuffered -f <this file + changes(f)>
#
# The stream opens with full workspace and window snapshots and then sends
# deltas. apply mirrors niri-ipc's EventStreamState (niri-ipc/src/state.rs)
# for the fields the bar reads; other events leave the state unchanged.

def apply($event):
  if $event.WorkspacesChanged then
    .workspaces = $event.WorkspacesChanged.workspaces
  elif $event.WorkspaceActivated.focused then
    $event.WorkspaceActivated.id as $id
    | .workspaces |= map(.is_focused = (.id == $id))
  elif $event.WorkspaceActiveWindowChanged then
    $event.WorkspaceActiveWindowChanged as $change
    | .workspaces |= map(
        if .id == $change.workspace_id then .active_window_id = $change.active_window_id else . end
      )
  elif $event.WindowsChanged then
    .windows = ($event.WindowsChanged.windows | INDEX(.id))
  elif $event.WindowOpenedOrChanged then
    $event.WindowOpenedOrChanged.window as $window
    | if $window.is_focused then .windows[].is_focused = false else . end
    | .windows[$window.id | tostring] = $window
  elif $event.WindowClosed then
    del(.windows[$event.WindowClosed.id | tostring])
  elif $event.WindowFocusChanged then
    $event.WindowFocusChanged.id as $id
    | .windows[] |= (.is_focused = (.id == $id))
  else
    .
  end;

def focused_window: first(.windows[] | select(.is_focused)) // null;

# Emits f once both snapshots have arrived, then whenever its value changes.
def changes(f):
  foreach inputs as $event ({state: {}};
    .state |= apply($event)
    | .previous = .current
    | .current = (.state | if .workspaces and .windows then [f] else null end);
    select(.current != .previous) | .current[0]);
