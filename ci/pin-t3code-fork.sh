#!/usr/bin/env bash
# The pin lane: pin the t3code-fork input to T3CODE_FORK_REV, a commit
# whexy/t3code's CI built and pushed to whexy-t3code.cachix.org, check it, and
# push it onto whatever master became meanwhile. A rev that is no longer the
# fork's head ends the lane as SUPERSEDED, without pinning.
set -euo pipefail
here=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source=ci/lib.sh
. "$here/lib.sh"

rev=${T3CODE_FORK_REV:-}
stage=validate
reported=
# Every failure names its stage, which the repair task reads.
on_exit() {
  local status=$?
  restore_origin
  if [ "$status" -ne 0 ] && [ -z "$reported" ]; then
    echo "FAILED($stage) - exit $status"
  fi
}
trap on_exit EXIT
fail() {
  echo "FAILED($stage) - $*"
  reported=1
  exit 1
}
push_failed() {
  fail "$1 attempts"
}
# Ends the run as SUPERSEDED once the fork has moved past rev. Failing to
# read the head is a failure, not a newer commit.
check_head() {
  if ! head=$(git ls-remote --exit-code https://github.com/whexy/t3code refs/heads/self-hosted-nightly); then
    fail "cannot read the head of whexy/t3code self-hosted-nightly"
  fi
  case $head in
  "$rev"[[:space:]]*) ;;
  *)
    echo "SUPERSEDED - $rev is no longer the head of whexy/t3code self-hosted-nightly"
    exit 0
    ;;
  esac
}

bot_identity
case $rev in
*[!0-9a-f]* | "") valid=false ;;
*) [ "$(printf %s "$rev" | wc -c)" -eq 40 ] && valid=true || valid=false ;;
esac
[ "$valid" = true ] || fail "T3CODE_FORK_REV is not a full commit hash: $rev"
check_head

# Every host substitutes the server, so its whole closure must be in Cachix
# or cache.nixos.org. A dry run against an empty store lists what Nix would
# have to build instead.
stage=cache
store=$(mktemp -d)
errors=$(mktemp)
for system in x86_64-linux aarch64-darwin; do
  if ! out=$(nix eval --raw "github:whexy/t3code/$rev#packages.$system.t3-server.outPath" 2>"$errors"); then
    cat "$errors"
    fail "cannot evaluate the $system t3-server"
  fi
  if ! plan=$(nix build --dry-run --store "$store" \
    --option substituters "https://cache.nixos.org https://whexy-t3code.cachix.org" \
    --option trusted-public-keys "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= whexy-t3code.cachix.org-1:/pDSZMaQ8YHPw/og8nsuwxiYCAAcRB8JYEcmNd2Czyg=" \
    "$out" 2>&1); then
    echo "$plan"
    fail "the dry run for the $system t3-server failed"
  fi
  case $plan in
  *"will be built"* | *"know how to build"*)
    echo "$plan"
    fail "the $system t3-server is not fully cached"
    ;;
  esac
  echo "OK - $system $out is cached"
done
rm -rf "$store" "$errors"

stage=pin
old=$(nix eval --raw --impure --expr '(builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.t3code-fork.locked.rev')
nix shell --inputs-from . nixpkgs#gnused -c sed -i "s|github:whexy/t3code/[0-9a-f]\{40\}|github:whexy/t3code/$rev|" flake.nix
# Nix caches a source's hash by commit alone, and a working tree of the fork
# at that commit hashes differently, so the lock gets a cache of its own
# (AGENTS.md, "The server package").
XDG_CACHE_HOME=$(mktemp -d) nix flake update t3code-fork
if git diff --quiet; then
  echo "NOOP - t3code-fork is already pinned to $rev"
  exit 0
fi
# The desktop app follows the version the new server builds.
nix run --accept-flake-config .#update -- t3code-desktop-nightly
version=$(nix eval --raw .#packages.x86_64-linux.t3code-fork.version)
git add -A
git commit -m "chore(t3code-fork): pin $rev ($version)" \
  -m "https://github.com/whexy/t3code/compare/$old...$rev"

stage=check
bash "$here/check.sh"

# Onto whatever master became meanwhile, as long as the rev is still the
# fork's head. A newer pin that landed first supersedes this one rather than
# conflicting with it.
rebase_onto_master() {
  check_head
  git fetch origin master
  if ! git rebase origin/master; then
    git rebase --abort
    check_head
    fail "the pin does not rebase onto master"
  fi
  check_head
}
stage=push
push_master 3 rebase_onto_master
echo "OK - pinned t3code-fork to $rev"
