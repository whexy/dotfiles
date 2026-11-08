# shellcheck shell=bash
# Sourced by the lanes that commit to master as the GitHub App.

bot_identity() {
  git config user.name "whexy-bot[bot]"
  git config user.email "315421218+whexy-bot[bot]@users.noreply.github.com"
}

# The origin URL from before push_master put the App's token into it. A lane
# calls restore_origin from its EXIT trap, so the token leaves the
# workspace's git config, which later steps share, however the lane ends.
ci_origin_url=
restore_origin() {
  if [ -n "$ci_origin_url" ]; then
    git remote set-url origin "$ci_origin_url"
  fi
}

# Ends the lane once every push failed; a lane may redefine it.
push_failed() {
  exit 1
}

# push_master ATTEMPTS [COMMAND...]: push HEAD to master as the GitHub App, up
# to ATTEMPTS times, waiting 10 s, 20 s, ... between them. COMMAND, if given,
# runs before each attempt, outside any condition, so a failure in it ends
# the lane under set -e.
push_master() {
  local attempts=$1 attempt=1 token
  shift
  token=$(nix run --accept-flake-config .#github-app-token)
  ci_origin_url=$(git remote get-url origin)
  git remote set-url origin "https://x-access-token:$token@github.com/whexy/dotfiles.git"
  while :; do
    if [ $# -gt 0 ]; then
      "$@"
    fi
    if git push origin HEAD:master; then
      return 0
    fi
    if [ "$attempt" -ge "$attempts" ]; then
      push_failed "$attempts"
    fi
    sleep $((attempt * 10))
    attempt=$((attempt + 1))
  done
}
