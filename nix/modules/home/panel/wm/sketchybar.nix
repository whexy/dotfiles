# SketchyBar window-manager items (macOS).
#
# Renders one item per workspace plus a front-app item, driven by AeroSpace
# or Paneru depending on dotfiles.wm.darwin.windowManager. Both WMs signal
# changes through the shared `wm_state_change` event (registered via the
# events extension point in ../sketchybar.nix): AeroSpace triggers it from
# its own hooks, while the paneru-events launchd agent bridges
# `paneru subscribe` into it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;

  sketchybar = lib.getExe pkgs.sketchybar;
  aerospace = lib.getExe pkgs.unstable.aerospace;
  paneru = lib.getExe config.services.paneru.finalPackage;
  jq = lib.getExe pkgs.jq;

  wmEnabled = config.dotfiles.wm.darwin.enable;
  windowManager = config.dotfiles.wm.darwin.windowManager;
  isPaneru = windowManager == "paneru";

  enabled = cfg.sketchybar.enable && pkgs.stdenv.hostPlatform.isDarwin;

  # Subset of the Liquid Glass palette in ../sketchybar.nix.
  colors = {
    fg = "0xffffffff";
    fgDim = "0xb3ffffff"; # 70% white, empty workspaces and the front app
    glass = "0x1affffff"; # 10% white, shared capsule backgrounds
    glassBorder = "0x40ffffff"; # 25% white hairline, capsule edge highlight
    blue = "0xff0a84ff"; # systemBlue, active workspace pill
  };

  mkPlugin = name: pkgs.writeShellScript "sketchybar-wm-${name}";

  # Workspace items live inside the shared `spaces` capsule (bracket below):
  # only the active workspace gets an inset blue pill, the rest are bare text.
  # Paneru workspaces are rendered together by paneruStatePlugin from one state
  # snapshot below.
  workspacePlugin = mkPlugin "workspace" ''
    set_state() {
      ${sketchybar} --set "$NAME" icon.highlight="$1" icon.color="$2" \
        background.drawing="$3" background.color="$4"
    }

    workspace="''${NAME#space.}"
    focused="''${FOCUSED_WORKSPACE:-$(${aerospace} list-workspaces --focused 2>/dev/null | /usr/bin/head -n 1)}"

    if [ "$workspace" = "$focused" ]; then
      set_state on ${colors.fg} on ${colors.blue}
    else
      set_state off ${colors.fgDim} off ${colors.blue}
    fi
  '';

  frontAppPlugin = mkPlugin "front-app" ''
    if [ "$SENDER" = "front_app_switched" ] && [ -n "''${INFO:-}" ]; then
      app="$INFO"
    else
      ${
        if isPaneru then
          ''app="$(${paneru} query active --json 2>/dev/null | ${jq} -r '.focused_app_name // empty')"''
        else
          ''app="$(${aerospace} list-windows --focused --format '%{app-name}' 2>/dev/null | /usr/bin/head -n 1)"''
      }
    fi

    ${sketchybar} --set "$NAME" label="''${app:-Desktop}"
  '';

  # Paneru events are invalidation hints rather than durable state. Query one
  # snapshot and update every WM item together so the bar always converges.
  paneruStatePlugin = mkPlugin "paneru-state" ''
    state="$(${paneru} query state --json 2>/dev/null)" || exit 0
    ${jq} -e '.active and (.virtual_workspaces | type == "array")' >/dev/null 2>&1 <<<"$state" || exit 0

    args=()
    for workspace in {1..9}; do
      workspace_state="$(${jq} -r --argjson n "$workspace" '
        .active.native_workspace_id as $native
        | first(
            .virtual_workspaces[]
            | select(.native_workspace_id == $native and .number == $n)
            | "\(.active) \(.windows | length)"
          ) // "false 0"
      ' <<<"$state")"
      active="''${workspace_state%% *}"
      count="''${workspace_state#* }"

      if [ "$active" = "true" ]; then
        highlight=on
        icon_color=${colors.fg}
        pill=on
      elif [ "$count" -gt 0 ] 2>/dev/null; then
        highlight=off
        icon_color=${colors.fg}
        pill=off
      else
        highlight=off
        icon_color=${colors.fgDim}
        pill=off
      fi
      args+=(--set "space.$workspace" icon.highlight="$highlight" icon.color="$icon_color" background.drawing="$pill")
    done

    app="$(${jq} -r '.active.focused_app_name // "Desktop"' <<<"$state")"
    args+=(--set front_app label="$app")
    ${sketchybar} "''${args[@]}"
  '';

  # Bridges `paneru subscribe` events into the sketchybar `wm_state_change`
  # event that workspace and front-app items subscribe to.
  paneruEventBridge = mkPlugin "paneru-events" ''
    while true; do
      if ${paneru} query state --json >/dev/null 2>&1; then
        # Reconcile state before subscribing so startup and reconnect gaps do
        # not leave the bar waiting indefinitely for the next Paneru event.
        ${sketchybar} --trigger wm_state_change
        ${paneru} subscribe --json | while IFS= read -r _event; do
          ${sketchybar} --trigger wm_state_change
        done
      fi
      /bin/sleep 1
    done
  '';

  workspaceItem = n: {
    name = "space.${toString n}";
    side = "left";
    settings = {
      icon = n;
      "label.drawing" = "off";
      "icon.padding_left" = 8;
      "icon.padding_right" = 8;
      padding_left = 1;
      padding_right = 1;
      # The shared `spaces` bracket supplies the capsule; a workspace only
      # draws its own background while active, as an inset blue pill.
      "background.drawing" = "off";
      "background.color" = colors.blue;
      "background.height" = 20;
      "background.corner_radius" = 10;
    }
    // lib.optionalAttrs (!isPaneru) { script = workspacePlugin; };
    clickScript =
      if isPaneru then
        "${paneru} send-cmd window virtualnum ${toString n}"
      else
        "${aerospace} workspace ${toString n}";
    subscribe = lib.optional (!isPaneru) "wm_state_change";
  };

  paneruStateItem = {
    name = "paneru_state";
    side = "left";
    settings = {
      drawing = "off";
      updates = "on";
      update_freq = 10;
      script = paneruStatePlugin;
    };
    subscribe = [
      "wm_state_change"
      "system_woke"
    ];
  };

  frontAppItem = {
    name = "front_app";
    side = "left";
    settings = {
      icon = "󰣆";
      "icon.color" = colors.fgDim;
      "label.color" = colors.fgDim;
      "label.max_chars" = 40;
    }
    // lib.optionalAttrs (!isPaneru) { script = frontAppPlugin; };
    subscribe = lib.optionals (!isPaneru) [
      "front_app_switched"
      "wm_state_change"
    ];
  };

  wmItems =
    (map workspaceItem (lib.range 1 9)) ++ lib.optional isPaneru paneruStateItem ++ [ frontAppItem ];

  mkAgent = name: programArguments: {
    enable = true;
    config = {
      ProgramArguments = programArguments;
      ProcessType = "Interactive";
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/${name}.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/${name}.err.log";
    };
  };
in
{
  config = lib.mkIf enabled {
    # Workspaces and the front app lead the bar's left side; other feature
    # modules (e.g. ai-quota) only add right-side items. The workspaces share
    # one capsule, drawn by the `spaces` bracket.
    dotfiles.panel.sketchybar = {
      items = lib.mkBefore wmItems;
      events = [ "wm_state_change" ];
      brackets = [
        {
          name = "spaces";
          members = map (n: "space.${toString n}") (lib.range 1 9);
          settings = {
            "background.drawing" = "on";
            "background.color" = colors.glass;
            "background.height" = 26;
            "background.corner_radius" = 13;
            "background.border_width" = 1;
            "background.border_color" = colors.glassBorder;
          };
        }
      ];
    };

    launchd.agents.sketchybar-paneru-events = lib.mkIf (wmEnabled && isPaneru) (
      mkAgent "sketchybar-paneru" [ "${paneruEventBridge}" ]
    );
  };
}
