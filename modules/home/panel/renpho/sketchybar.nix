# Renpho weight pill for SketchyBar (macOS).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;

  sketchybar = lib.getExe pkgs.sketchybar;

  enabled = cfg.renpho.enable && cfg.sketchybar.enable && pkgs.stdenv.hostPlatform.isDarwin;

  # Subset of the Liquid Glass palette in ../sketchybar.nix.
  colors = {
    gray = "0xff98989d"; # systemGray, stale or fetch error
    purple = "0xffbf5af2"; # systemPurple, neutral reading
  };

  weightScript = import ./weight.nix { inherit config lib pkgs; };

  pillPlugin = pkgs.writeShellScript "sketchybar-renpho" ''
    weight="$(${weightScript})"
    stale=$?
    if [ -z "$weight" ]; then
      ${sketchybar} --set "$NAME" icon.color=${colors.gray} label="…"
      exit 0
    fi
    color=${colors.purple}
    [ "$stale" -eq 0 ] || color=${colors.gray}
    ${sketchybar} --set "$NAME" drawing=on icon.color="$color" label="$weight"kg
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
