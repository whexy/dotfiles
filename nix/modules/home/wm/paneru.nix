# Paneru sliding window manager configuration (macOS, experimental)
{
  config,
  lib,
  ...
}:
let
  cfg = config.dotfiles.wm;
  enabled = cfg.darwin.enable && cfg.darwin.windowManager == "paneru";
  bottomPadding = if config.dotfiles.panel.sketchybar.enable then 34 else 0;
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
            preset_column_widths = { 0.25, 0.33, 0.5, 0.66, 0.75, 1.0, 1.5, 2.0 },
            auto_center = false,
            window_resize_cycle = true,
            virtual_workspace_animations = false,
            reap_empty_workspaces = true,
          },
          padding = { top = 0, bottom = ${toString bottomPadding}, left = 0, right = 0 },
          swipe = {
            sensitivity = 0.35,
            deceleration = 4.0,
            continuous = true,
            scroll = { modifier = meh },
          },
          restore = { enabled = false },
          decorations = {
            workspace_menu_status = false,
            workspace_popup_status = false,
          },
          windows = {
            ghostty = {
              title = ".*",
              bundle_id = "com.mitchellh.ghostty",
              width = 0.5,
            },
          },
          bindings = {
            ["window focus west"] = hyper .. " - h",
            ["window focus east"] = hyper .. " - l",

            ["window swap west"] = meh .. " - h",
            ["window swap east"] = meh .. " - l",

            ["window shrink"] = meh .. " - minus",
            ["window grow"] = meh .. " - equal",
            ["window resize"] = meh .. " - slash",
            ["window manage"] = hyper .. " - f",
            ["window center"] = meh .. " - c",
            ["window fullwidth"] = meh .. " - f",
          },
        }

        paneru.bind(meh .. " - m", "window fullwidth")
        paneru.bind(hyper .. " - v", function(ws)
          local focused = ws:focused()
          local window = focused and ws:window(focused)
          paneru.run(window and window.floating and "window focus managed" or "window focus unmanaged")
        end)

        paneru.bind(hyper .. " - space", function() os.execute([[/usr/bin/open -a "Alfred 5"]]) end)
        paneru.bind(meh .. " - space", function() os.execute([[/usr/bin/open -a "Alfred 5"]]) end)
        paneru.bind(hyper .. " - c", function()
          os.execute([[ /usr/bin/osascript -e 'tell application "System Events" to keystroke "c" using {command down, option down}' ]])
        end)
        paneru.bind(hyper .. " - t", function() os.execute("/usr/bin/open -na Ghostty") end)
        paneru.bind(hyper .. " - q", function()
          os.execute([[ /usr/bin/osascript -e 'tell application "System Events" to keystroke "w" using command down' ]])
        end)
        paneru.bind(hyper .. " - a", function() os.execute("/usr/sbin/screencapture -i") end)
        paneru.bind(hyper .. " - o", function()
          os.execute([[ /usr/bin/osascript -e 'tell application "System Events" to key code 126 using control down' ]])
        end)
        paneru.bind(hyper .. " - p", function() os.execute("/usr/bin/pmset displaysleepnow") end)
      '';
    };

    warnings = [
      "Paneru support is experimental and configured conservatively for one virtual row per native Space. Multi-monitor virtual workspaces and cross-display movement are intentionally not configured."
    ];
  };
}
