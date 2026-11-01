# Uses an item in the vaults this home's service account reads, without
# printing the value. The Nix preamble sets `vaults` (IDs, in search order),
# `named` (the items.nix references), and `token`, which reaches op through
# its environment alone.

usage() {
  cat >&2 <<'USAGE'
usage: op-sa show <item>
       op-sa run <VAR>=<item>[/<field>]... -- <command> [<arg>...]
       op-sa read <item>[/<field>]

<item> is a name from modules/home/onepassword/items.nix, or an item ID or
title in the dotfiles or dotfiles-dev vault. Without /<field>, the item's
only concealed field or file is meant.
USAGE
  exit 2
}

op_() {
  OP_SERVICE_ACCOUNT_TOKEN=$token op "$@"
}

# The item's JSON, values included, for a variable and never for output. A
# service account must name the vault, so an item given by ID or title is
# looked for in each.
item_json() {
  local ref vault
  if ref=$(named "$1"); then
    ref=${ref#op://}
    vault=${ref%%/*}
    ref=${ref#*/}
    op_ item get "${ref%%/*}" --vault "$vault" --format json
    return
  fi
  for vault in "${vaults[@]}"; do
    if op_ item get "$1" --vault "$vault" --format json 2>/dev/null; then
      return
    fi
  done
  echo "op-sa: this home reads no item $1" >&2
  return 1
}

# Field IDs and file names name a value in a secret reference.
resolve() {
  local spec=$1 item field="" json
  # A name is already a reference, read in one request.
  if [[ $spec != */* ]] && named "$spec"; then
    return
  fi
  item=${spec%%/*}
  if [[ $spec == */* ]]; then
    field=${spec#*/}
  fi
  json=$(item_json "$item") || return 1
  if ! jq -er --arg field "$field" '
    . as $item
    | [((.fields // [])[] | {key: .id, label, concealed: (.type == "CONCEALED")}),
       ((.files // [])[] | {key: .name, label: .name, concealed: true})]
    | map(select(if $field == "" then .concealed else .key == $field or .label == $field end))
    | select(length == 1)
    | "op://\($item.vault.id)/\($item.id)/\(.[0].key)"
  ' <<<"$json"; then
    echo "op-sa: $spec names no single value; add /<field> from:" >&2
    describe <<<"$json" >&2
    return 1
  fi
}

describe() {
  jq -r '
    "\(.title) (\(.category)), item \(.id) in vault \(.vault.name)",
    ((.fields // [])[] | select(.purpose != "NOTES")
      | "  field \(.label) [\(.type)]" + (if .section.label then " in section \(.section.label)" else "" end)),
    ((.files // [])[] | "  file \(.name) (\(.size) bytes)")
  '
}

[ "$#" -ge 2 ] || usage
command=$1
shift
case "$command" in
show)
  [ "$#" -eq 1 ] || usage
  json=$(item_json "$1")
  describe <<<"$json"
  ;;
read)
  [ "$#" -eq 1 ] || usage
  ref=$(resolve "$1")
  op_ read --no-newline "$ref"
  ;;
run)
  refs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    if ! [[ $1 =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
      usage
    fi
    var=${BASH_REMATCH[1]}
    ref=$(resolve "${BASH_REMATCH[2]}")
    refs+=("$var=$ref")
    shift
  done
  [ "$#" -ge 2 ] && [ "${#refs[@]}" -gt 0 ] || usage
  shift
  # op run swaps each reference for its value and masks the values in the
  # command's output. The command never gets the service-account token.
  export OP_SERVICE_ACCOUNT_TOKEN=$token
  exec env "${refs[@]}" op run -- env -u OP_SERVICE_ACCOUNT_TOKEN "$@"
  ;;
*)
  usage
  ;;
esac
