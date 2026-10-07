#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
metadata="$repo_root/packages/t3code-nightly/metadata.nix"
registry=$(curl -fsSL https://registry.npmjs.org/t3)
version=$(sed -n 's/.*"nightly":"\([^"]*\)".*/\1/p' <<<"$registry")

if [ -z "$version" ]; then
  echo "t3code-nightly: could not resolve the npm nightly dist-tag" >&2
  exit 1
fi

hashes=()
for platform in linux-x64 linux-arm64 darwin-arm64; do
  url="https://registry.npmjs.org/@t3code/t3-${platform}/-/t3-${platform}-${version}.tgz"
  hash=$(nix store prefetch-file --json --hash-type sha256 "$url" | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p')
  if [ -z "$hash" ]; then
    echo "t3code-nightly: could not hash $url" >&2
    exit 1
  fi
  hashes+=("$hash")
done

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<EOF
{
  version = "$version";

  hashes = {
    darwin-arm64 = "${hashes[2]}";
    linux-arm64 = "${hashes[1]}";
    linux-x64 = "${hashes[0]}";
  };
}
EOF

if cmp -s "$tmp" "$metadata"; then
  echo "t3code-nightly: already pinned to $version"
else
  mv "$tmp" "$metadata"
  trap - EXIT
  echo "t3code-nightly: pinned $version"
fi
