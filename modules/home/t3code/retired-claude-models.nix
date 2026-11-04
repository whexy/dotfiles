# Removes the gateway models earlier activations wrote into T3's Claude
# provider as custom models. Claude Code now reports the gateway's models
# itself, and T3 lists them; the old entries have other slugs, so they would
# list every model twice.
#
# dotfiles-settings.json beside T3's settings records which custom models
# those activations wrote, so models added in T3 itself stay. The record goes
# once they are removed, after which this does nothing; it can be deleted once
# every home has activated it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  jq = lib.getExe pkgs.jq;

  cleanup = pkgs.writeShellScript "t3-retire-claude-models" ''
    set -eo pipefail
    userdata=${lib.escapeShellArg "${config.home.homeDirectory}/.t3/userdata"}
    settings="$userdata/settings.json"
    state="$userdata/dotfiles-settings.json"

    [ -e "$state" ] || exit 0
    if ! owned=$(${jq} -c '.ownedClaudeModels // []' "$state"); then
      echo "t3-retire-claude-models: could not read $state; leaving it unchanged" >&2
      exit 0
    fi

    replace() {
      local temporary
      temporary=$(mktemp "$userdata/.$(basename "$1").XXXXXX")
      printf '%s\n' "$2" >"$temporary"
      chmod 644 "$temporary"
      mv "$temporary" "$1"
    }

    if [ -e "$settings" ]; then
      before=$(cat "$settings")
      if ! after=$(${jq} --argjson owned "$owned" '
        if .providerInstances.claudeAgent.config.customModels == null then .
        else .providerInstances.claudeAgent.config.customModels |= map(
          select((if type == "string" then . else .slug end) as $slug
            | any($owned[]; . == $slug) | not)
        )
        end
      ' <<<"$before"); then
        echo "t3-retire-claude-models: could not update $settings; leaving it unchanged" >&2
        exit 0
      fi
      # T3 rewrites the file itself; one it changed meanwhile is left, with
      # the record, for the next activation.
      if ! ${jq} -e --argjson after "$after" '. == $after' <<<"$before" >/dev/null; then
        if [ "$(cat "$settings")" != "$before" ]; then
          echo "t3-retire-claude-models: $settings changed while editing; the next activation retries" >&2
          exit 0
        fi
        replace "$settings" "$after"
      fi
    fi

    rest=$(${jq} -c 'del(.ownedClaudeModels)' "$state")
    if [ "$rest" = "{}" ]; then
      rm -f "$state"
    else
      replace "$state" "$rest"
    fi
  '';
in
{
  config = lib.mkIf config.dotfiles.t3code.enable {
    home.activation.t3codeRetireClaudeModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${cleanup}
    '';
  };
}
