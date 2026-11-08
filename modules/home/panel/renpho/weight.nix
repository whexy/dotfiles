# The script behind every bar's Renpho pill. Prints the latest weight in kg
# (nothing before the first successful fetch) and exits 1 when that value may
# be stale: the last fetch failed or the server's Renpho sync did.
#
# The zepbound Worker answers with `sync.next_check_at`, the earliest time
# newer data can exist, so the response is cached and the network is touched
# only after that time. The bars still tick every few minutes; a tick before
# then reads the cache. Several machines run this script at once, and the
# Worker folds their simultaneous requests into one Renpho sync.
{
  config,
  lib,
  pkgs,
}:
let
  coreutils = "${pkgs.coreutils}/bin";
  curl = lib.getExe pkgs.curl;
  jq = lib.getExe pkgs.jq;
  cfIdFile = config.dotfiles.cloudflareAccess.serviceToken.idPath;
  cfSecretFile = config.dotfiles.cloudflareAccess.serviceToken.secretPath;
  dataUrl = "https://zepbound.whexy.com/api/data.json";
in
pkgs.writeShellScript "renpho-weight" ''
  dir="''${XDG_CACHE_HOME:-$HOME/.cache}/renpho"
  cache="$dir/data.json"
  ${coreutils}/mkdir -p "$dir"

  stale=0
  if ! ${jq} -e '(.sync.next_check_at | fromdateiso8601) > now' "$cache" >/dev/null 2>&1; then
    tmp="$(${coreutils}/mktemp "$dir/.data.XXXXXX")"
    # Headers go through stdin: argv is readable by every local user.
    if printf 'CF-Access-Client-Id: %s\nCF-Access-Client-Secret: %s\n' \
        "$(<"${cfIdFile}")" "$(<"${cfSecretFile}")" \
      | ${curl} -fsS --max-time 15 -H @- -o "$tmp" "${dataUrl}" 2>/dev/null \
      && ${jq} -e '.measurements | length > 0' "$tmp" >/dev/null 2>&1; then
      ${coreutils}/mv -f "$tmp" "$cache"
    else
      ${coreutils}/rm -f "$tmp"
      stale=1
    fi
  fi

  ${jq} -r '(.measurements | max_by(.date) | .weight_kg) // empty' "$cache" 2>/dev/null
  ${jq} -e '.sync.status == "error"' "$cache" >/dev/null 2>&1 && stale=1
  exit "$stale"
''
