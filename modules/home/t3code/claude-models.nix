# The gateway's non-Claude models, added to T3's Claude provider.
#
# T3's Claude provider lists only Claude's own models. It starts Claude Code
# through the `claude` launcher, which sends any model to the gateway Claude
# Code is set to, so the provider's custom models add every other model that
# CLIProxyAPI, Claude Code's default gateway, serves. They fail while
# claude-select names another gateway or the claude.ai login. Claude's own
# models stay T3's, whose catalog knows their options.
#
# dotfiles-settings.json beside T3's settings records the models this wrote,
# so models the gateway drops are removed and ones added in T3 survive.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.t3code;
  gateway = config.dotfiles.llmGateways.gateways.cliproxyapi;
  inherit (config.dotfiles.llmGateways) accessToken;
  jq = lib.getExe pkgs.jq;

  claudeModels = pkgs.writeShellScriptBin "t3-claude-models" ''
    set -eo pipefail
    userdata=${lib.escapeShellArg "${config.home.homeDirectory}/.t3/userdata"}
    settings="$userdata/settings.json"
    state="$userdata/dotfiles-settings.json"

    # The agenix paths expand XDG_RUNTIME_DIR, which an activation outside
    # the user's session lacks; the reads then fail and the list stays.
    # Credentials reach curl on stdin, never on its command line.
    if ! key=$(<"${gateway.apiKeyPath}") ||
      ! accessId=$(<"${accessToken.idPath}") ||
      ! accessSecret=$(<"${accessToken.secretPath}") ||
      ! catalog=$(
        printf 'Authorization: Bearer %s\nCF-Access-Client-Id: %s\nCF-Access-Client-Secret: %s\n' \
          "$key" "$accessId" "$accessSecret" |
          ${lib.getExe pkgs.curl} --fail --silent --show-error --max-time 10 \
            --header @- ${lib.escapeShellArg gateway.catalogUrl}
      ); then
      echo "t3-claude-models: could not list ${gateway.name}'s models; T3 Code's Claude models are unchanged" >&2
      exit 0
    fi

    # The catalog is Codex's, so it also lists effort levels Claude Code
    # does not take.
    if ! models=$(${jq} -c '
      {low: "Low", medium: "Medium", high: "High", xhigh: "Extra High", max: "Max"} as $labels
      | [.models[]
          | select(.visibility != "hide" and (.slug | startswith("claude-") | not))
          | .default_reasoning_level as $default
          | {
              slug,
              name: (.display_name // .slug),
              capabilities: {
                optionDescriptors: [
                  [.supported_reasoning_levels[]?.effort | select($labels[.] != null)]
                  | select(length > 0)
                  | {
                      id: "effort",
                      label: "Reasoning",
                      type: "select",
                      options: map({id: ., label: $labels[.]} + (if . == $default then {isDefault: true} else {} end))
                    }
                ]
              }
            }]
    ' <<<"$catalog"); then
      echo "t3-claude-models: ${gateway.name} answered without a model catalog; T3 Code's Claude models are unchanged" >&2
      exit 0
    fi

    read_settings() {
      if [ -e "$settings" ]; then
        cat "$settings"
      else
        echo '{}'
      fi
    }

    mkdir -p "$userdata"
    before=$(read_settings)
    owned=$(${jq} -c '.ownedClaudeModels // []' "$state" 2>/dev/null) || owned='[]'
    if ! after=$(${jq} --argjson models "$models" --argjson owned "$owned" '
      ($owned + [$models[].slug]) as $replaced
      | .providerInstances.claudeAgent |= (
          (. // {driver: "claudeAgent"})
          | .config.customModels |= (
              [(. // [])[]
                | select((if type == "string" then . else .slug end) as $slug
                    | any($replaced[]; . == $slug) | not)]
              + $models
            )
        )
    ' <<<"$before"); then
      echo "t3-claude-models: could not update $settings; leaving it unchanged" >&2
      exit 0
    fi

    replace() {
      local temporary
      temporary=$(mktemp "$userdata/.$(basename "$1").XXXXXX")
      printf '%s\n' "$2" >"$temporary"
      chmod 644 "$temporary"
      mv "$temporary" "$1"
    }

    # T3 rebuilds its Claude provider whenever its settings change, so an
    # unchanged list is not written. T3 also rewrites the file itself, so a
    # file it changed meanwhile is left for the next run.
    if ! ${jq} -e --argjson after "$after" '. == $after' <<<"$before" >/dev/null; then
      if [ "$(read_settings)" != "$before" ]; then
        echo "t3-claude-models: $settings changed while editing; run t3-claude-models again" >&2
        exit 0
      fi
      replace "$settings" "$after"
    fi
    replace "$state" "$(${jq} -n --argjson models "$models" '{ownedClaudeModels: [$models[].slug]}')"
  '';
in
{
  config = lib.mkIf cfg.enable {
    age.secrets = config.dotfiles.llmGateways.secrets;

    home = {
      packages = [ claudeModels ];
      activation.t3codeClaudeModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe claudeModels}
      '';
    };
  };
}
