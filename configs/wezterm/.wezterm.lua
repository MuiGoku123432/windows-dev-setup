local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Color scheme
config.color_scheme = "Catppuccin Mocha"

-- Font
config.font = wezterm.font_with_fallback({
  "JetBrainsMono Nerd Font",
  "Consolas",
})
config.font_size = 12

-- Default shell: Nushell
config.default_prog = { "nu" }

-- Window appearance
config.window_padding = {
  left = 8,
  right = 8,
  top = 8,
  bottom = 8,
}
config.initial_cols = 140
config.initial_rows = 40

-- Tab bar
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true

-- Disable update checks (managed by winget)
config.check_for_updates = false

return config
