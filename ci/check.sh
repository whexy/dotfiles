#!/usr/bin/env bash
# Check HEAD's tree: build every check but the host closures, then evaluate
# every host and standalone home without building it, each in its own process
# (ci/eval-all.sh). Building the closures, as `nix flake check` would, is too
# heavy for one CI pod. A tree that passes is recorded in the CI cache, so a
# pull request that lands on master unchanged is not checked again.
set -euo pipefail
here=$(dirname "${BASH_SOURCE[0]}")

tree=$(git rev-parse 'HEAD^{tree}')
passed=$(nix eval --raw --expr "builtins.toFile \"dotfiles-ci-passed\" \"$tree\"")
if nix path-info --store "$CI_CACHE_ENDPOINT/nix" "$passed" >/dev/null 2>&1; then
  echo "OK - tree $tree already passed"
  exit 0
fi

system=$(nix eval --raw --impure --expr builtins.currentSystem)
checks=()
for name in $(nix eval --raw ".#checks.$system" --apply 'cs: builtins.concatStringsSep "\n"
  (builtins.filter (n: builtins.match "(nixos|darwin)-.*" n == null) (builtins.attrNames cs))'); do
  checks+=(".#checks.$system.$name")
done
nix build --accept-flake-config "${checks[@]}" -L --no-link

# A skill edit can break its frontmatter or a patch over it, which the
# agent-skills check above has already caught. Beyond that, Nix passes
# skills through as paths and reads markdown only as text, so editing them
# can break evaluation only by removing a file.
docs_only=$(nix eval --impure --expr '
  let files = builtins.fromJSON (builtins.getEnv "CI_PIPELINE_FILES"); in
  files != [ ] && builtins.all (f:
    builtins.match "docs/.*|.*[.]md|modules/home/agents/skills/.*" f != null
    && builtins.pathExists (./. + ("/" + f))
  ) files' 2>/dev/null) || docs_only=false
if [ "$docs_only" = true ]; then
  echo "OK - only docs, markdown and skills changed"
  exit 0
fi

EVAL_JOBS=${EVAL_JOBS:-3} bash "$here/eval-all.sh"

# nix-ci uploads only what it builds, so every Pod would otherwise fetch the
# flake inputs from GitHub and cache.nixos.org again.
keyfile=$(mktemp)
printf '%s' "$NIX_CACHE_SIGNING_KEY" | tr -d '[:space:]' >"$keyfile"
store="s3://nix?endpoint=$CI_CACHE_ENDPOINT&region=us-east-1&compression=zstd&multipart-upload=true&secret-key=$keyfile"
timeout 300 nix flake archive --accept-flake-config --to "$store" ||
  echo "Could not upload the flake inputs"
nix copy --to "$store" "$passed" || echo "Could not record that tree $tree passed"
rm -f "$keyfile"
