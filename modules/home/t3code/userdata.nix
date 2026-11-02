# Sets one key of a JSON document in T3's userdata, keeping the keys T3
# wrote there. A plain function of the home, returning the script's package.
{
  lib,
  pkgs,
  homeDirectory,
}:
{
  name,
  file,
  key,
  value,
}:
let
  jq = lib.getExe pkgs.jq;
  json = lib.escapeShellArg (builtins.toJSON value);
in
pkgs.writeShellScriptBin name ''
  set -eo pipefail
  userdata=${lib.escapeShellArg "${homeDirectory}/.t3/userdata"}
  document="$userdata/${file}"
  if ${jq} -e --argjson value ${json} '.${key} == $value' "$document" >/dev/null 2>&1; then
    exit 0
  fi
  if [ ! -e "$document" ]; then
    after=$(${jq} -n --argjson value ${json} '{${key}: $value}')
  elif ! after=$(${jq} --argjson value ${json} '.${key} = $value' "$document"); then
    echo "${name}: could not update $document; leaving it unchanged" >&2
    exit 0
  fi
  mkdir -p "$userdata"
  temporary=$(mktemp "$userdata/.${file}.XXXXXX")
  printf '%s\n' "$after" >"$temporary"
  chmod 644 "$temporary"
  mv "$temporary" "$document"
''
