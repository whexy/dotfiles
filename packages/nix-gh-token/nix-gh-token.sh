out=""
scopes=()

while [ $# -gt 0 ]; do
  case "$1" in
  --out)
    out="${2:-}"
    shift 2
    ;;
  --help | -h)
    echo "usage: nix-gh-token --out <file> <host/owner>..."
    exit 0
    ;;
  *)
    scopes+=("$1")
    shift
    ;;
  esac
done

if [ -z "$out" ]; then
  echo "nix-gh-token: --out is required" >&2
  exit 2
fi

token=$(gh auth token 2>/dev/null || true)

if [ ${#scopes[@]} -eq 0 ]; then
  rm -f "$out"
  exit 0
fi

# A logged-out `gh` still exits 0 in some configurations, so emptiness of the
# output is the only reliable signal.
if [ -z "$token" ]; then
  exit 0
fi

# `gh auth token` hands back whatever is stored, revoked or not, and Nix's
# tarball fetcher hard-fails with HTTP 401 on a rejected token instead of
# retrying anonymously. Probe the token so a rotated one is dropped rather
# than materialised. `gh api` exits 1 when offline too, so the verdict is
# the status line `--include` prints only once GitHub has answered.
response=$(GH_TOKEN="$token" gh api user --include --silent 2>/dev/null || true)
read -r _ status _ <<<"$response" || true
case "$status" in
200) ;;
401)
  echo "nix-gh-token: stored gh token was rejected by GitHub; removing $out" >&2
  rm -f "$out"
  exit 0
  ;;
*)
  echo "nix-gh-token: could not verify the gh token; leaving $out unchanged" >&2
  exit 0
  ;;
esac

entries=""
for scope in "${scopes[@]}"; do
  entries="$entries $scope=$token"
done

mkdir -p "$(dirname "$out")"

umask 077
tmp=$(mktemp "$out.XXXXXX")
chmod 600 "$tmp"

# `extra-` appends instead of replacing, so this never clobbers tokens that a
# host or the daemon configured elsewhere.
printf 'extra-access-tokens =%s\n' "$entries" >"$tmp"
mv -f "$tmp" "$out"
