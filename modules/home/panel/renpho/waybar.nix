# Renpho weight pill for Waybar (Linux).
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.panel;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;

  curl = lib.getExe pkgs.curl;
  cfIdFile = config.age.secrets.cf-access-dotfiles-id.path;
  cfSecretFile = config.age.secrets.cf-access-dotfiles-secret.path;
  dataUrl = "https://zepbound.whexy.com/api/data.json";
  jq = lib.getExe pkgs.jq;
  icon = "󰓅";

  enabled = cfg.renpho.enable && cfg.waybar.enable && cfg.linuxBar == "waybar" && (!isDarwin);

  pillScript = pkgs.writeShellScript "waybar-renpho" ''
    weight="$(${curl} -fsS --max-time 15 \
      -H "CF-Access-Client-Id: $(<"${cfIdFile}")" \
      -H "CF-Access-Client-Secret: $(<"${cfSecretFile}")" \
      "${dataUrl}" 2>/dev/null \
      | ${jq} -r '(.measurements | sort_by(.date) | last | .weight_kg) // empty' 2>/dev/null)"
    if [ -z "$weight" ]; then
      exec ${jq} -cn --arg icon '${icon}' '{text: ($icon + " …"), class: "stale"}'
    fi
    exec ${jq} -cn --arg icon '${icon}' --arg weight "$weight" '{text: ($icon + " " + $weight + "kg")}'
  '';
in
{
  config = lib.mkIf enabled {
    programs.waybar.settings.mainBar = {
      "modules-right" = lib.mkAfter [ "custom/renpho" ];

      "custom/renpho" = {
        exec = pillScript;
        interval = 300;
        return-type = "json";
      };
    };

    programs.waybar.style = lib.mkAfter ''
      #custom-renpho {
        padding: 2px 10px;
        margin: 3px 2px;
        border-radius: 10px;
        background-color: #3c3836;
        color: #d3869b;
        transition: all 0.3s ease;
      }

      #custom-renpho.stale { color: #928374; }

      #custom-renpho:hover {
        background-color: #d3869b;
        color: #282828;
      }
    '';
  };
}
