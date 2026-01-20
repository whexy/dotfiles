local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.initial_cols = 160
config.initial_rows = 48
config.font_size = 16
config.color_scheme = "Gruvbox Dark (Gogh)"
config.font = wezterm.font("FiraCode Nerd Font")
config.window_decorations = "RESIZE"

return config
