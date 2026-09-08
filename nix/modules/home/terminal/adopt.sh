# Move an existing job into a fresh multiplexer session with reptyr.
#
# reptyr resumes a stopped target itself and moves it into its own session, so
# the calling shell's job table is never mutated. A failed migration therefore
# leaves the job exactly as it was and `fg` still recovers it. The migrated
# process also survives the old shell exiting, which is why no `disown`
# handshake is needed here.
#
# `backend` and `reptyr` are set by the Nix prelude prepended to this file.

self="to$backend"

die() {
  printf '%s: %s\n' "$self" "$1" >&2
  exit 1
}

note() {
  printf '%s: %s\n' "$self" "$1" >&2
}

usage() {
  cat >&2 <<EOF
usage: $self [options] [PID]

Move a running or Ctrl-Z suspended job into a new $backend session using
reptyr. With no PID, adopts the calling shell's only stopped job.

Options:
  -t, --tree          steal the whole terminal session instead of one process
                      (reptyr -T); use for pipelines and subprocess trees
  -s, --force-stdio   attach fds 0-2 even without a controlling tty (reptyr -s)
  -n, --no-attach     create the session but stay in the current terminal
      --no-relax-yama do not touch kernel.yama.ptrace_scope; migration then
                      only works if the target called PR_SET_PTRACER itself
      --name NAME     session name (default: adopt-<command>-<pid>)
      --timeout SECS  migration handshake timeout (default: 20)
  -h, --help          show this help
EOF
}

tree=0
force_stdio=0
attach=1
# kernel.yama.ptrace_scope defaults to 1 wherever the Yama LSM is built in, which
# is every stock NixOS kernel. At that setting a tracer must be an ancestor of
# the target, and reptyr traces from a forked child that is only ever a sibling,
# so no ordinary job is attachable unless the target opted in via PR_SET_PTRACER.
# Relaxing the sysctl for the migration is therefore the normal path.
relax_yama=1
session=""
pid=""
timeout=20

while [ $# -gt 0 ]; do
  case "$1" in
  -t | --tree) tree=1 ;;
  -s | --force-stdio) force_stdio=1 ;;
  -n | --no-attach) attach=0 ;;
  --relax-yama) relax_yama=1 ;;
  --no-relax-yama) relax_yama=0 ;;
  --name)
    [ $# -ge 2 ] || die "--name needs an argument"
    session=$2
    shift
    ;;
  --timeout)
    [ $# -ge 2 ] || die "--timeout needs an argument"
    timeout=$2
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*) die "unknown option: $1" ;;
  *)
    [ -z "$pid" ] || die "unexpected argument: $1"
    pid=$1
    ;;
  esac
  shift
done

# Without an explicit PID, the target is the calling shell's stopped child.
# A standalone script cannot read the shell's job table, but %+ after Ctrl-Z is
# almost always the shell's only stopped child.
if [ -z "$pid" ]; then
  stopped=$(ps -o pid= -o stat= --ppid "$PPID" | awk '$2 ~ /^T/ { print $1 }')
  count=$(printf '%s' "$stopped" | grep -c . || true)
  case "$count" in
  0) die "no stopped job in the calling shell; suspend one with Ctrl-Z or pass a PID" ;;
  1) pid=$stopped ;;
  *)
    note "several stopped jobs, pass one explicitly:"
    read -r -a stopped_pids <<<"$(printf '%s' "$stopped" | tr '\n' ' ')"
    ps -o pid=,args= -p "${stopped_pids[@]}" >&2
    exit 1
    ;;
  esac
fi

case "$pid" in
'' | *[!0-9]*) die "not a PID: $pid" ;;
esac

kill -0 "$pid" 2>/dev/null || die "no such process: $pid"
[ "$(ps -o uid= -p "$pid" | tr -d ' ')" = "$(id -u)" ] || die "process $pid belongs to another user"

old_tty=$(ps -o tty= -p "$pid" | tr -d ' ')
comm=$(ps -o comm= -p "$pid" | tr -cd '[:alnum:]_-')
[ -n "$session" ] || session="adopt-${comm:-job}-$pid"

# reptyr refuses a target that shares its process group with other processes,
# because moving one member would split the group across two terminals.
if [ "$tree" = 0 ]; then
  pgid=$(ps -o pgid= -p "$pid" | tr -d ' ')
  peers=$(pgrep -g "$pgid" | grep -vx "$pid" || true)
  if [ -n "$peers" ]; then
    note "process $pid shares its process group with:"
    read -r -a peer_pids <<<"$(printf '%s' "$peers" | tr '\n' ' ')"
    ps -o pid=,args= -p "${peer_pids[@]}" >&2
    die "single-process migration would split that group; retry with --tree"
  fi
fi

yama_path=/proc/sys/kernel/yama/ptrace_scope
yama_orig=0
yama_relaxed=0
[ -r "$yama_path" ] && yama_orig=$(cat "$yama_path")

restore_yama() {
  if [ "$yama_relaxed" = 1 ]; then
    sudo -n sysctl -q -w "kernel.yama.ptrace_scope=$yama_orig" 2>/dev/null || true
    yama_relaxed=0
  fi
}

# The window stays open only until the migration is observed; restore_yama runs
# on the success path before attaching and from the EXIT trap on every failure.
if [ "$yama_orig" != 0 ] && [ "$relax_yama" = 1 ]; then
  if sudo -n sysctl -q -w kernel.yama.ptrace_scope=0 2>/dev/null; then
    yama_relaxed=1
  else
    # Not fatal: a target that opted in with PR_SET_PTRACER is still attachable,
    # and a genuine denial is reported with context once reptyr fails.
    note "could not relax kernel.yama.ptrace_scope=$yama_orig (needs passwordless sudo); trying anyway"
  fi
fi

statedir=$(mktemp -d)
# Removing statedir does not disturb the already-open script fd in the new
# pane, and the pane guards its own late writes.
trap 'restore_yama; rm -rf "$statedir"' EXIT

rc_file="$statedir/rc"
err_file="$statedir/err"
runner="$statedir/run.sh"

flags=""
[ "$tree" = 1 ] && flags="$flags -T"
[ "$force_stdio" = 1 ] && flags="$flags -s"

cat >"$runner" <<EOF
#!/usr/bin/env bash
$reptyr$flags $pid 2>"$err_file"
printf '%s' "\$?" >"$rc_file" 2>/dev/null || true
exec "\${SHELL:-/bin/sh}"
EOF
chmod +x "$runner"

create_session() {
  case "$backend" in
  tmux)
    tmux new-session -d -s "$session" "$runner"
    ;;
  zellij)
    zellij attach --create-background "$session" >/dev/null
    zellij --session "$session" run -- "$runner" >/dev/null
    ;;
  herdr)
    local created
    created=$(herdr tab create --cwd "$PWD" --label "$session" --no-focus) ||
      die "could not create a herdr tab; is a herdr session running?"
    herdr_tab=$(printf '%s' "$created" | jq -er '.result.tab.tab_id')
    herdr_pane=$(printf '%s' "$created" | jq -er '.result.root_pane.pane_id')
    herdr pane run "$herdr_pane" "$runner" >/dev/null
    ;;
  esac
}

destroy_session() {
  case "$backend" in
  tmux) tmux kill-session -t "$session" 2>/dev/null || true ;;
  zellij) zellij delete-session "$session" --force >/dev/null 2>&1 || true ;;
  herdr) [ -n "${herdr_tab:-}" ] && herdr tab close "$herdr_tab" >/dev/null 2>&1 || true ;;
  esac
}

attach_session() {
  case "$backend" in
  tmux)
    if [ -n "${TMUX:-}" ]; then
      tmux switch-client -t "$session"
    else
      tmux attach-session -t "$session"
    fi
    ;;
  zellij)
    if [ -n "${ZELLIJ:-}" ]; then
      note "already inside zellij; attach elsewhere with: zellij attach $session"
    else
      zellij attach "$session"
    fi
    ;;
  herdr)
    if [ "${HERDR_ENV:-}" = 1 ]; then
      herdr tab focus "$herdr_tab" >/dev/null
    else
      local running
      running=$(herdr session list | awk 'NR > 1 && $2 == "running" { print $1; exit }')
      [ -n "$running" ] || die "no running herdr session to attach to"
      herdr session attach "$running"
    fi
    ;;
  esac
}

# reptyr keeps running as the target's proxy until the target exits, so its own
# exit status cannot report a successful migration. A changed controlling
# terminal is the observable condition that the move actually happened.
migrated() {
  local now
  now=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ') || return 1
  [ -n "$now" ] && [ "$now" != "$old_tty" ]
}

failed_early() {
  [ -s "$rc_file" ] && [ "$(cat "$rc_file")" != 0 ]
}

report_failure() {
  if [ -s "$err_file" ]; then
    sed "s/^/$self: reptyr: /" "$err_file" >&2
  fi
  if [ "$yama_orig" != 0 ] && [ "$yama_relaxed" = 0 ]; then
    if [ "$relax_yama" = 0 ]; then
      note "kernel.yama.ptrace_scope=$yama_orig is the most likely cause; drop --no-relax-yama"
    else
      note "kernel.yama.ptrace_scope=$yama_orig is the most likely cause; relaxing it needs passwordless sudo"
    fi
  fi
  if kill -0 "$pid" 2>/dev/null; then
    note "job $pid left as-is (state $(ps -o stat= -p "$pid" | tr -d ' ')); recover it with fg"
  fi
}

create_session

if [ "$tree" = 1 ]; then
  # -T steals the original terminal's master fd rather than moving the
  # process, so the target keeps its tty and only reptyr's survival can
  # distinguish success from failure.
  sleep 3
  if failed_early; then
    destroy_session
    report_failure
    die "terminal steal failed"
  fi
else
  deadline=$((SECONDS + timeout))
  while :; do
    if migrated; then
      break
    fi
    if failed_early || ! kill -0 "$pid" 2>/dev/null; then
      destroy_session
      report_failure
      die "migration failed"
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      destroy_session
      report_failure
      die "timed out after ${timeout}s waiting for $pid to change terminal"
    fi
    sleep 0.1
  done
fi

restore_yama

if [ "$tree" = 1 ]; then
  note "stole the terminal of $pid into $backend session '$session'"
else
  note "moved $pid from $old_tty to $(ps -o tty= -p "$pid" | tr -d ' ') in $backend session '$session'"
  note "the old shell still lists it as a job; disown it there to exit that shell cleanly"
fi

if [ "$attach" = 1 ]; then
  attach_session
fi
