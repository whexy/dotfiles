#!/usr/bin/env bash
# The update lane: update every flake input and every package that pins an
# upstream release, one commit each, then check the commits and push them to
# master. The check runs on the updated tree as it stands; nothing fetches or
# rebases before the push, which fails if master moved meanwhile.
set -euo pipefail
here=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source=ci/lib.sh
. "$here/lib.sh"
trap restore_origin EXIT

bot_identity
start=$(git rev-parse HEAD)

# The input and release lookups below make more GitHub API calls than the 60
# an hour an unauthenticated runner IP gets, so they run as the GitHub App:
# Nix through access-tokens, the updater through GITHUB_TOKEN. The token
# expires within the hour, so the check and push go without it.
nix_config=${NIX_CONFIG:-}
GITHUB_TOKEN="$(nix run --accept-flake-config .#github-app-token)"
export GITHUB_TOKEN
export NIX_CONFIG="$nix_config
access-tokens = github.com=$GITHUB_TOKEN"

old_lock=$(mktemp)
cp flake.lock "$old_lock"
nix flake update
if git diff --quiet -- flake.lock; then
  echo "No changes to flake.lock"
else
  git add flake.lock
  # The package report is informational; a failure must not block the update.
  report="$(nix run --accept-flake-config .#flake-lock-diff -- --jobs 2 "$old_lock")" ||
    report="Package report unavailable; see the CI log."
  # The push records a rollout status; the tree cache reuses this check.
  git commit -m "chore: update flake inputs" -m "$report"
fi

# The driver reverts a package it cannot update and exits non-zero at the
# end, so the other updates are still checked and pushed before the lane
# fails and report-failure runs.
updated=0
nix run --accept-flake-config .#update -- --commit || updated=$?

export NIX_CONFIG="$nix_config"
unset GITHUB_TOKEN

if [ "$(git rev-parse HEAD)" = "$start" ]; then
  echo "Nothing to update"
  exit "$updated"
fi
bash "$here/check.sh"
push_master 4
exit "$updated"
