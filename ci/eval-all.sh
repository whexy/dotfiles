#!/usr/bin/env bash
# Evaluate every configuration a host can switch to: each NixOS and Darwin
# system and each standalone home. Auto-upgrade switches hosts to any commit
# CI passes, so a configuration left out here could break unnoticed. Each
# evaluation is its own nix process, so no process holds more than one
# configuration's memory (about 2 GB); EVAL_JOBS of them run at once.
#
# Blueprint publishes standalone homes for every system, and the hosts do not
# say which one their machine is, so homes are evaluated for x86_64-linux.
set -euo pipefail

jobs=${EVAL_JOBS:-1}
log=$(mktemp -d)
trap 'rm -rf "$log"' EXIT

names() {
  nix eval --raw ".#$1" --apply 'c: builtins.concatStringsSep "\n" (builtins.attrNames c)'
}

targets=()
for name in $(names nixosConfigurations); do
  targets+=("nixosConfigurations.$name.config.system.build.toplevel")
done
for name in $(names darwinConfigurations); do
  targets+=("darwinConfigurations.$name.system")
done
for name in $(names legacyPackages.x86_64-linux.homeConfigurations); do
  targets+=("legacyPackages.x86_64-linux.homeConfigurations.\"$name\".activationPackage")
done

evaluate() {
  local target=$1 out
  out="$log/$(printf %s "$target" | tr -c 'A-Za-z0-9._-' _)"
  if nix eval --accept-flake-config --raw --show-trace ".#$target.drvPath" >"$out.drv" 2>"$out.err"; then
    echo "OK   $target $(cat "$out.drv")"
  else
    cat "$out.err" >&2
    echo "FAIL $target"
    touch "$out.failed"
  fi
}

running=0
for target in "${targets[@]}"; do
  if [ "$running" -ge "$jobs" ]; then
    wait -n
    running=$((running - 1))
  fi
  evaluate "$target" &
  running=$((running + 1))
done
wait

failed=$(find "$log" -name '*.failed' | wc -l)
if [ "$failed" -ne 0 ]; then
  echo "$failed of ${#targets[@]} configurations do not evaluate" >&2
  exit 1
fi
echo "OK - all ${#targets[@]} configurations evaluate"
