# The script behind every bar's Renpho pill. Prints the latest weight in kg
# (nothing before the first successful fetch) and exits 1 when that value may
# be stale: the last fetch failed or the server's Renpho sync did.
#
# The zepbound Worker answers with `sync.next_check_at`, the earliest time
# newer data can exist, so the response is cached and the network is touched
# only after that time. The bars still tick every few minutes; a tick before
# then reads the cache. Several machines run this script at once, and the
# Worker folds their simultaneous requests into one Renpho sync. Each fetch
# loads the Access token from 1Password, whose requests are rationed, so a
# failed fetch waits 15 minutes before the next.
{
  config,
  lib,
  pkgs,
}:
let
  coreutils = "${pkgs.coreutils}/bin";
  curl = lib.getExe pkgs.curl;
  jq = lib.getExe pkgs.jq;
  opSa = lib.getExe config.dotfiles.onepassword.package;
  dataUrl = "https://zepbound.whexy.com/api/data.json";
in
pkgs.writeShellScript "renpho-weight" ''
  dir="''${XDG_CACHE_HOME:-$HOME/.cache}/renpho"
  cache="$dir/data.json"
  ${coreutils}/mkdir -p "$dir"

  stale=0
  failed="$dir/failed"
  if ! ${jq} -e '(.sync.next_check_at | fromdateiso8601) > now' "$cache" >/dev/null 2>&1; then
    if [ -n "$(${pkgs.findutils}/bin/find "$failed" -mmin -15 2>/dev/null)" ]; then
      stale=1
    else
      tmp="$(${coreutils}/mktemp "$dir/.data.XXXXXX")"
      # Headers go through stdin: argv is readable by every local user.
      if printf 'CF-Access-Client-Id: %s\nCF-Access-Client-Secret: %s\n' \
          "$(${opSa} read cf-access-dotfiles-id 2>/dev/null)" "$(${opSa} read cf-access-dotfiles-secret 2>/dev/null)" \
        | ${curl} -fsS --max-time 15 -H @- -o "$tmp" "${dataUrl}" 2>/dev/null \
        && ${jq} -e '.measurements | length > 0' "$tmp" >/dev/null 2>&1; then
        ${coreutils}/mv -f "$tmp" "$cache"
        ${coreutils}/rm -f "$failed"
      else
        ${coreutils}/rm -f "$tmp"
        ${coreutils}/touch "$failed"
        stale=1
      fi
    fi
  fi

  ${jq} -r '(.measurements | max_by(.date) | .weight_kg) // empty' "$cache" 2>/dev/null
  ${jq} -e '.sync.status == "error"' "$cache" >/dev/null 2>&1 && stale=1
  exit "$stale"
''
