local wezterm = require "wezterm"

local config = {}

if wezterm.config_builder then
  config = wezterm.config_builder()
end

config.default_prog = { "/bin/zsh", "-l" }
config.color_scheme = "Tokyo Night"
config.font = wezterm.font "JetBrains Mono"
config.font_size = 16.0
config.window_background_opacity = 0.96
config.window_padding = {
  left = 10,
  right = 10,
  top = 8,
  bottom = 8,
}
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.scrollback_lines = 50000
config.enable_scroll_bar = false
config.adjust_window_size_when_changing_font_size = false

config.keys = {
  { key = "h", mods = "CTRL|SHIFT", action = wezterm.action.ActivatePaneDirection "Left" },
  { key = "j", mods = "CTRL|SHIFT", action = wezterm.action.ActivatePaneDirection "Down" },
  { key = "k", mods = "CTRL|SHIFT", action = wezterm.action.ActivatePaneDirection "Up" },
  { key = "l", mods = "CTRL|SHIFT", action = wezterm.action.ActivatePaneDirection "Right" },
  { key = "d", mods = "CTRL|SHIFT", action = wezterm.action.SplitHorizontal { domain = "CurrentPaneDomain" } },
  { key = "r", mods = "CTRL|SHIFT", action = wezterm.action.SplitVertical { domain = "CurrentPaneDomain" } },
  { key = "w", mods = "CTRL|SHIFT", action = wezterm.action.CloseCurrentPane { confirm = true } },
  { key = "t", mods = "CTRL|SHIFT", action = wezterm.action.SpawnTab "CurrentPaneDomain" },
  { key = "LeftArrow", mods = "CTRL|SHIFT", action = wezterm.action.ActivateTabRelative(-1) },
  { key = "RightArrow", mods = "CTRL|SHIFT", action = wezterm.action.ActivateTabRelative(1) },
  { key = "Enter", mods = "ALT", action = wezterm.action.ToggleFullScreen },
}

return config
