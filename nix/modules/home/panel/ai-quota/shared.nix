# Shared plumbing for the AI-quota bar pills (Waybar and Eww renderers).
#
# Owns the provider list, the shared JSON cache path, and the cache
# refresh; both renderers read the same cache. Summarization logic lives
# in ./summary.jq.
{
  config,
  pkgs,
  perSystem,
  ...
}:
let
  aiQuota = "${perSystem.self.ai-quota}/bin/ai-quota";
  cacheFile = "${config.xdg.cacheHome}/ai-quota.json";

  providers = [
    {
      name = "kimi";
      icon = "󰽥";
    }
    {
      name = "codex";
      icon = "󰚩";
    }
  ];

  # Refreshes the shared JSON cache both renderers poll.
  updateCacheScript = pkgs.writeShellScript "ai-quota-update-cache" ''
    out="$(${aiQuota} --json 2>/dev/null)" || exit 0
    mkdir -p "$(dirname "${cacheFile}")"
    tmp="${cacheFile}.tmp.$$"
    printf '%s\n' "$out" > "$tmp"
    mv "$tmp" "${cacheFile}"
  '';
in
{
  inherit
    aiQuota
    cacheFile
    providers
    updateCacheScript
    ;
}
