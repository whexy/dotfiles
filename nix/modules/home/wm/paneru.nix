# Paneru sliding window manager configuration (macOS, experimental)
args@{
  config,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.wm;
  enabled = cfg.darwin.enable && cfg.darwin.windowManager == "paneru";
  autoHideMenuBar = osConfig != null && (osConfig.dotfiles.hardware.display.autoHideMenuBar or true);
  macbookScreen = osConfig != null && (osConfig.dotfiles.hardware.display.macbookScreen or true);
  topPadding =
    if (config.dotfiles.panel.sketchybar.enable && autoHideMenuBar && (!macbookScreen)) then 34 else 0;
  bottomPadding = if (config.dotfiles.panel.sketchybar.enable && !autoHideMenuBar) then 34 else 0;
in
{
  config = lib.mkIf enabled {
    services.paneru = {
      enable = true;
      luaConfig.enable = true;

      # Lua is used only for actions Paneru does not expose as native commands,
      # such as launching applications and invoking macOS utilities.
      config = ''
        local hyper = "ctrl + alt + shift + cmd"
        local meh = "ctrl + alt + cmd"

        paneru.setup {
          default_workspaces = 1,
          options = {
            focus_follows_mouse = false,
            mouse_follows_focus = true,
            horizontal_mouse_warp = 1,
            preset_column_widths = { 0.33, 0.5, 0.66 },
            auto_center = false,
            window_resize_cycle = true,
            virtual_workspace_animations = false,
            reap_empty_workspaces = true,
            ${lib.optionalString autoHideMenuBar "menubar_height = 0,\n"}
          },
          padding = { top = ${toString topPadding}, bottom = ${toString bottomPadding}, left = 0, right = 0 },
          restore = { enabled = false },
          decorations = {
            -- Native macOS dimming of inactive windows (opacity only, no color).
            inactive = { dim = { opacity = -0.06 } },
            -- Experimental: colored border around the focused window.
            active = { border = { enabled = true, color = "#89b4fa", width = 2.0 } },
          },
          windows = {
            ghostty = {
              title = ".*",
              bundle_id = "com.mitchellh.ghostty",
              width = 0.5,
            },
            firefox = {
              title = ".*",
              bundle_id = "org.mozilla.firefox",
              width = 0.66,
            },
          },
          bindings = {
            ["window focus west"] = hyper .. " - h",
            ["window focus east"] = hyper .. " - l",
            ["window focus north"] = hyper .. " - k",
            ["window focus south"] = hyper .. " - j",

            ["window swap west"] = meh .. " - h",
            ["window swap east"] = meh .. " - l",
            ["window swap north"] = meh .. " - k",
            ["window swap south"] = meh .. " - j",

            ["window resize"] = meh .. " - /",
            ["window fullwidth"] = meh .. " - f",

            ["window manage"] = hyper .. " - f",
            ["window stack"] = meh .. " - [",
            ["window unstack"] = meh .. " - ]",

            ["window nextdisplay"] = meh .. " - rightarrow",
            ["mouse nextdisplay"] = hyper .. " - rightarrow",
          },
        }

        -- Remember the last focused managed window per virtual workspace, so
        -- switching workspaces can restore it (like `window focus managed`,
        -- which cannot be chained after a workspace switch without racing).
        paneru.on("window_focused", function(event, ws)
          local window = ws:window(event.window_id)
          if window and not window.floating then
            paneru.state.set("last_focused." .. ws:current(), event.window_id)
          end
        end)

        for i = 1, 9 do
          -- Switch to virtual workspace i and focus its previously focused
          -- managed window. view + focus are committed atomically by
          -- returning the transformed window set, so they cannot race.
          paneru.bind(hyper .. " - " .. i, function(ws)
            ws = ws:view(i)
            local target = paneru.state.get("last_focused." .. i)
            local window = target and ws:window(target)
            if window and not window.floating and ws:workspace_of(target) == i then
              return ws:focus(target)
            end
            -- Fallback: focus the first managed window on that workspace.
            for _, w in ipairs(ws:workspace_windows(i)) do
              if not w.floating then
                return ws:focus(w.id)
              end
            end
            return ws
          end)
          paneru.bind(meh .. " - " .. i, "window virtualmovenum " .. i)
        end

        paneru.bind(hyper .. " - v", function(ws)
          local focused = ws:focused()
          local window = focused and ws:window(focused)
          paneru.run(window and window.floating and "window focus managed" or "window focus unmanaged")
        end)

        paneru.bind(hyper .. " - space", function() os.execute([[/usr/bin/env -i /usr/bin/open -a "Alfred 5"]]) end)
        paneru.bind(hyper .. " - t", function() os.execute("/usr/bin/env -i /usr/bin/open -na Ghostty") end)
      '';
    };

    warnings = [
      "Paneru support is experimental and configured conservatively for one virtual row per native Space. Multi-monitor virtual workspaces and cross-display movement are intentionally not configured."
    ];
  };
}
