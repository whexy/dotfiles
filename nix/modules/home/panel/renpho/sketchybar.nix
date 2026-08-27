# Renpho weight pill for SketchyBar (macOS).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;

  curl = lib.getExe pkgs.curl;
  cfIdFile = config.age.secrets.cf-access-dotfiles-id.path;
  cfSecretFile = config.age.secrets.cf-access-dotfiles-secret.path;
  dataUrl = "https://zepbound.whexy.com/api/data.json";
  sketchybar = lib.getExe pkgs.sketchybar;
  jq = lib.getExe pkgs.jq;

  enabled = cfg.renpho.enable && cfg.sketchybar.enable && pkgs.stdenv.hostPlatform.isDarwin;

  # Subset of the Liquid Glass palette in ../sketchybar.nix.
  colors = {
    gray = "0xff98989d"; # systemGray, fetch error
    purple = "0xffbf5af2"; # systemPurple, neutral reading
  };

  pillPlugin = pkgs.writeShellScript "sketchybar-renpho" ''
    weight="$(${curl} -fsS --max-time 15 \
      -H "CF-Access-Client-Id: $(<"${cfIdFile}")" \
      -H "CF-Access-Client-Secret: $(<"${cfSecretFile}")" \
      "${dataUrl}" 2>/dev/null \
      | ${jq} -r '(.measurements | sort_by(.date) | last | .weight_kg) // empty' 2>/dev/null)"
    if [ -z "$weight" ]; then
      ${sketchybar} --set "$NAME" icon.color=${colors.gray} label="…"
      exit 0
    fi
    ${sketchybar} --set "$NAME" drawing=on icon.color=${colors.purple} label="$weight"kg
  '';

  pillItem = {
    name = "renpho";
    side = "right";
    settings = {
      icon = "󰓅";
      "icon.color" = colors.purple;
      update_freq = 300;
      script = pillPlugin;
    };
    subscribe = [ "system_woke" ];
  };
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.sketchybar.items = [ pillItem ];
  };
}
