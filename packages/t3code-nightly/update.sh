#!/usr/bin/env bash
set -euo pipefail

script_dir=${BASH_SOURCE[0]%/*}
[ "$script_dir" != "${BASH_SOURCE[0]}" ] || script_dir=.
repo_root=$(cd "$script_dir/../.." && pwd)

# The nixos/nix CI image ships without most text tools, so take them from the
# flake's pinned nixpkgs instead of the caller's PATH.
if [ -z "${T3CODE_UPDATE_TOOLS:-}" ]; then
  T3CODE_UPDATE_TOOLS=1 exec nix shell --inputs-from "$repo_root" \
    nixpkgs#bash nixpkgs#coreutils nixpkgs#curl nixpkgs#diffutils \
    nixpkgs#gawk nixpkgs#gnused nixpkgs#gnutar nixpkgs#gzip \
    -c bash "${BASH_SOURCE[0]}" "$@"
fi

metadata="$repo_root/packages/t3code-nightly/metadata.nix"
dist_tags=$(curl -fsSL https://registry.npmjs.org/-/package/t3/dist-tags)
version=$(sed -n 's/.*"nightly":"\([^"]*\)".*/\1/p' <<<"$dist_tags")

if [ -z "$version" ]; then
  echo "t3code-nightly: could not resolve the npm nightly dist-tag" >&2
  exit 1
fi

# T3 stopped publishing per-platform npm packages after 0.1.1-nightly.3190:
# the `t3` npm package is now a shim that downloads the matching archive from
# the GitHub Release and verifies it against that release's SHA256SUMS. Pin
# those hashes. Only the linux-x64 archive, which carries the browser pin
# below, has to be downloaded.
release_base="https://github.com/pingdotgg/t3code/releases/download/v${version}"
sums=$(curl -fsSL "$release_base/SHA256SUMS")
sum_for() {
  awk -v archive="t3-${version}-$1.tar.gz" '$2 == archive { print $1 }' <<<"$sums"
}
hashes=()
for platform in linux-x64 linux-arm64 darwin-arm64; do
  hash=$(sum_for "$platform")
  if [ -z "$hash" ]; then
    echo "t3code-nightly: t3-${version}-${platform}.tar.gz not listed in $release_base/SHA256SUMS" >&2
    exit 1
  fi
  hashes+=("$(nix hash convert --hash-algo sha256 --to sri "$hash")")
done

url="$release_base/t3-${version}-linux-x64.tar.gz"
prefetch=$(nix store prefetch-file --json --hash-type sha256 --expected-hash "${hashes[0]}" "$url")
tarball=$(sed -n 's/.*"storePath": *"\([^"]*\)".*/\1/p' <<<"$prefetch")

# T3 downloads a pinned Chrome for Testing headless shell at runtime, which
# cannot load its libraries on NixOS. The server source embedded in the
# executable carries the pin, so read it from there to package the same build.
browser_pins=$(
  tar -xzOf "$tarball" "t3-${version}-linux-x64/t3" |
    LC_ALL=C sed -n '\#^//\#region src/preview/PreviewBrowser.ts$#,/chromePlatform = /p' |
    LC_ALL=C awk '
      /VERSION = "/ { match($0, /"[^"]+"/); print "version", substr($0, RSTART + 1, RLENGTH - 2) }
      /^\t\t"?[a-z0-9-]+"?: \{/ { p = $1; gsub(/[":]/, "", p) }
      p && /sha256:/ { match($0, /"[0-9a-f]+"/); print p, substr($0, RSTART + 1, RLENGTH - 2); p = "" }
    '
)
browser_pin() {
  awk -v key="$1" '$1 == key { print $2 }' <<<"$browser_pins"
}
browser_version=$(browser_pin version)
browser_linux64=$(browser_pin linux64)
browser_linux_arm64=$(browser_pin linux-arm64)
if [ -z "$browser_version" ] || [ -z "$browser_linux64" ] || [ -z "$browser_linux_arm64" ]; then
  echo "t3code-nightly: could not read the headless browser pin from t3" >&2
  exit 1
fi
browser_linux64=$(nix hash convert --hash-algo sha256 --to sri "$browser_linux64")
browser_linux_arm64=$(nix hash convert --hash-algo sha256 --to sri "$browser_linux_arm64")

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

  browser = {
    version = "$browser_version";
    hashes = {
      linux-arm64 = "$browser_linux_arm64";
      linux64 = "$browser_linux64";
    };
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
