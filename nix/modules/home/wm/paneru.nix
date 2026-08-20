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
  bottomPadding = if config.dotfiles.panel.sketchybar.enable then 34 else 0;
  menubarHeight =
    if osConfig != null && !(osConfig.dotfiles.hardware.display.macbookScreen or false) then
      0
    else
      null;
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
        ${
          lib.optionalString (
            menubarHeight != null
          ) "            menubar_height = ${toString menubarHeight},\n"
        }          },
                  padding = { top = 0, bottom = ${toString bottomPadding}, left = 0, right = 0 },
                  restore = { enabled = false },
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

                paneru.bind(hyper .. " - v", function(ws)
                  local focused = ws:focused()
                  local window = focused and ws:window(focused)
                  paneru.run(window and window.floating and "window focus managed" or "window focus unmanaged")
                end)

                paneru.bind(hyper .. " - space", function() os.execute([[/usr/bin/open -a "Alfred 5"]]) end)
                paneru.bind(hyper .. " - t", function() os.execute("/usr/bin/open -na Ghostty") end)
      '';
    };

    warnings = [
      "Paneru support is experimental and configured conservatively for one virtual row per native Space. Multi-monitor virtual workspaces and cross-display movement are intentionally not configured."
    ];
  };
}
