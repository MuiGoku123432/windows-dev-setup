local wezterm = require("wezterm")
local act = wezterm.action
local config = {}

-- If you use the config builder (newer wezterm), this is also fine:
-- local config = wezterm.config_builder()

-- Your default shell (optional)
-- config.default_prog = { "nu" } -- or {"wsl.exe","-d","Ubuntu","--cd","~","nu"} on Windows/WSL

-- Leader key (tmux style)
config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 1000 }

-- Optional: make it easier to see tabs
config.show_tab_index_in_tab_bar = true

config.keys = {
	-- Split panes
	{ key = "-", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "\\", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },

	-- Pane controls (mode-based key tables)
	{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

	-- Enter resize mode (then use h/j/k/l repeatedly, Esc to exit)
	{
		key = "r",
		mods = "LEADER",
		action = act.ActivateKeyTable({
			name = "resize_pane",
			one_shot = false,
		}),
	},

	-- Tabs
	{ key = "c", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "n", mods = "LEADER", action = act.ActivateTabRelative(1) },
	{ key = "p", mods = "LEADER", action = act.ActivateTabRelative(-1) },

	-- Jump directly to tabs 1..9
	{ key = "1", mods = "LEADER", action = act.ActivateTab(0) },
	{ key = "2", mods = "LEADER", action = act.ActivateTab(1) },
	{ key = "3", mods = "LEADER", action = act.ActivateTab(2) },
	{ key = "4", mods = "LEADER", action = act.ActivateTab(3) },
	{ key = "5", mods = "LEADER", action = act.ActivateTab(4) },
	{ key = "6", mods = "LEADER", action = act.ActivateTab(5) },
	{ key = "7", mods = "LEADER", action = act.ActivateTab(6) },
	{ key = "8", mods = "LEADER", action = act.ActivateTab(7) },
	{ key = "9", mods = "LEADER", action = act.ActivateTab(8) },

	-- Pane/tab actions
	{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "z", mods = "LEADER", action = act.TogglePaneZoomState },

	-- Send Ctrl-a to terminal (for apps that use it) by pressing leader then Ctrl-a
	{ key = "a", mods = "LEADER|CTRL", action = act.SendKey({ key = "a", mods = "CTRL" }) },
}

-- Resize mode: leader + r, then h/j/k/l repeatedly, Esc to leave
config.key_tables = {
	resize_pane = {
		{ key = "h", action = act.AdjustPaneSize({ "Left", 3 }) },
		{ key = "j", action = act.AdjustPaneSize({ "Down", 3 }) },
		{ key = "k", action = act.AdjustPaneSize({ "Up", 3 }) },
		{ key = "l", action = act.AdjustPaneSize({ "Right", 3 }) },
		{ key = "Escape", action = "PopKeyTable" },
		{ key = "Enter", action = "PopKeyTable" },
	},
}

return config
