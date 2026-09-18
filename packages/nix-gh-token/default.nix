{ pkgs }:

# Materialises the GitHub CLI's token as a nix.conf fragment so `nix` can fetch
# private `github:` flakes. Writing a fragment rather than exporting NIX_CONFIG
# keeps the token out of the environment of every process `nix run` spawns.
#
# Absent or logged-out `gh` removes the fragment instead of writing an empty or
# stale one: a scoped-but-invalid token makes every fetch under that scope fail
# with HTTP 401, which is strictly worse than having no token at all.
pkgs.writeShellScriptBin "nix-gh-token" ''
  set -euo pipefail

  out=""
  scopes=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --out)
        out="''${2:-}"
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

  token=""
  if [ -x "${pkgs.gh}/bin/gh" ]; then
    token=$(${pkgs.gh}/bin/gh auth token 2>/dev/null || true)
  fi

  # A logged-out `gh` still exits 0 in some configurations, so emptiness of the
  # output is the only reliable signal.
  if [ -z "$token" ] || [ ''${#scopes[@]} -eq 0 ]; then
    ${pkgs.coreutils}/bin/rm -f "$out"
    exit 0
  fi

  entries=""
  for scope in "''${scopes[@]}"; do
    entries="$entries $scope=$token"
  done

  ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$out")"

  umask 077
  tmp=$(${pkgs.coreutils}/bin/mktemp "$out.XXXXXX")
  ${pkgs.coreutils}/bin/chmod 600 "$tmp"

  # `extra-` appends instead of replacing, so this never clobbers tokens that a
  # host or the daemon configured elsewhere.
  printf 'extra-access-tokens =%s\n' "$entries" > "$tmp"
  ${pkgs.coreutils}/bin/mv -f "$tmp" "$out"
''
