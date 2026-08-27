# Renpho weight widget for Eww (Linux).
#
# One Eww poll fetches current measurements and emits the complete summary as
# JSON. The visible widget consumes that value directly.
args@{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.panel;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;

  renphoHealth = lib.getExe inputs.renpho-health.packages.${pkgs.stdenv.hostPlatform.system}.default;
  credsFile = config.age.secrets.renpho-creds.path;
  jq = lib.getExe pkgs.jq;
  summaryFilter = ./summary.jq;
  icon = "󰓅";
  summaryCount = 5;

  enabled = cfg.renpho.enable && cfg.waybar.enable && cfg.linuxBar == "eww" && (!isDarwin);

  summaryScript = pkgs.writeShellScript "eww-renpho" ''
    raw="$(${renphoHealth} recent --count ${toString summaryCount} --creds-file "${credsFile}" 2>/dev/null)" || exit 0
    printf '%s\n' "$raw" | ${jq} -c --argjson summary_count ${toString summaryCount} -f ${summaryFilter} 2>/dev/null
  '';
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.eww = {
      defs = ''
        (defpoll RENPHO :interval "300s"
          :initial '{"present":false,"state":"stale","lines":[]}'
          "${summaryScript}")

        (defwidget renpho []
          (box :class {"pill renpho " + jq(RENPHO, ".state")}
            :tooltip {jq(RENPHO, ".lines | join(\"\\n\")")}
            (label :text {
              "${icon} "
              + (jq(RENPHO, ".present")
                ? round(jq(RENPHO, ".weight"), 1) + "kg"
                  + (jq(RENPHO, ".trend") == "" ? "" : " " + jq(RENPHO, ".trend")
                    + (jq(RENPHO, ".delta == null") ? "" : jq(RENPHO, ".delta")))
                : "…")})))
      '';

      right = lib.mkAfter [ "renpho" ];

      styles = ''
        .renpho {
          color: #efb876;
        }
      '';
    };
  };
}
