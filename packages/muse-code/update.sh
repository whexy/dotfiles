#!/usr/bin/env bash
set -euo pipefail

script_dir=${BASH_SOURCE[0]%/*}
[ "$script_dir" != "${BASH_SOURCE[0]}" ] || script_dir=.
repo_root=$(cd "$script_dir/../.." && pwd)

# The nixos/nix CI image ships without most text tools, so take them from the
# flake's pinned nixpkgs instead of the caller's PATH.
if [ -z "${MUSE_CODE_UPDATE_TOOLS:-}" ]; then
  MUSE_CODE_UPDATE_TOOLS=1 exec nix shell --inputs-from "$repo_root" \
    nixpkgs#bash nixpkgs#coreutils nixpkgs#curl nixpkgs#gnused nixpkgs#jq \
    -c bash "${BASH_SOURCE[0]}" "$@"
fi

metadata="$repo_root/packages/muse-code/metadata.nix"
channel=$(curl -fsSL https://api.meta.ai/muse-code/channels/muse-stable)
version=$(jq -r .version <<<"$channel")
manifest_url=$(jq -r .manifest_url <<<"$channel")
if [ -z "$version" ] || [ "$version" = null ] || [ -z "$manifest_url" ] || [ "$manifest_url" = null ]; then
  echo "muse-code: could not read the channel manifest" >&2
  exit 1
fi

manifest=$(curl -fsSL "$manifest_url")
hash_for() {
  local artifact hash
  artifact=$(jq -r --arg p "$1" '.artifacts[$p].checksum' <<<"$manifest")
  if [ -z "$artifact" ] || [ "$artifact" = null ]; then
    echo "muse-code: no checksum for $1 in the release manifest" >&2
    exit 1
  fi
  hash=$(nix hash convert --hash-algo sha256 --to sri "$artifact")
  printf '%s' "$hash"
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<EOF
{
  version = "$version";

  hashes = {
    aarch64-darwin = "$(hash_for aarch64_macos)";
    aarch64-linux = "$(hash_for aarch64_linux)";
    x86_64-darwin = "$(hash_for x86_macos)";
    x86_64-linux = "$(hash_for x86_linux)";
  };
}
EOF

if cmp -s "$tmp" "$metadata"; then
  echo "muse-code: already pinned to $version"
else
  mv "$tmp" "$metadata"
  trap - EXIT
  echo "muse-code: pinned $version"
fi
