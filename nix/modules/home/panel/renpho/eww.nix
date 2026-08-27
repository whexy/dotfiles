# Renpho weight widget for Eww (Linux).
#
# One Eww poll fetches the latest measurement from the zepbound JSON cache.
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

  enabled = cfg.renpho.enable && cfg.waybar.enable && cfg.linuxBar == "eww" && (!isDarwin);

  weightScript = pkgs.writeShellScript "eww-renpho" ''
    ${curl} -fsS --max-time 15 \
      -H "CF-Access-Client-Id: $(<"${cfIdFile}")" \
      -H "CF-Access-Client-Secret: $(<"${cfSecretFile}")" \
      "${dataUrl}" 2>/dev/null \
      | ${jq} -r '(.measurements | sort_by(.date) | last | .weight_kg) // empty' 2>/dev/null
  '';
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.eww = {
      defs = ''
        (defpoll RENPHO :interval "300s"
          :initial ""
          "${weightScript}")

        (defwidget renpho []
          (box :class "pill renpho"
            (label :text {"${icon} " + (RENPHO == "" ? "…" : RENPHO + "kg")})))
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
