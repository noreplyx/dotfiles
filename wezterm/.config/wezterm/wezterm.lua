local wezterm = require "wezterm"
-- NOTE: wezterm.plugin.require currently ignores the { tag = ... } option (it
-- clones the default branch); it documents intent. Reviewed pin: v1.6.0 ==
-- 6022b9f9ec68c9a4dd50f40ceba3a7b9b9d1684a; keep in sync with setup.sh PINNED_TABLINE_SHA;
-- setup.sh verifies and forces the cached plugin clone to that SHA. Plugins
-- never auto-update after first clone; update manually via
-- wezterm.plugin.update_all().
local tabline = wezterm.plugin.require("https://github.com/michaelbrusegard/tabline.wez", { tag = "v1.6.0" })

local config = {}

if wezterm.config_builder then
  config = wezterm.config_builder()
end

config.default_prog = { "/bin/zsh", "-l" }
config.color_scheme = "Tokyo Night"
config.font = wezterm.font_with_fallback({ "JetBrains Mono", "MesloLGS Nerd Font Mono" })
config.font_size = 16.0
config.window_background_opacity = 0.96
config.window_padding = {
  left = 10,
  right = 10,
  top = 8,
  bottom = 8,
}
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

-- Armed by the tab-bar ✕ (OnClick). Enter opens wezterm's native close-tab
-- confirmation dialog, which names the tab being closed by its first pane's
-- terminal title (NOT the tabline's index+cwd label, so it may be hard to
-- recognize); Escape cancels; the 4s ActivateKeyTable timeout auto-cancels.
-- NOTE: the '_mode' suffix is load-bearing — tabline's mode
-- component only displays/themes keytables named *_mode, AND an unknown
-- *_mode name crashes tabline's render path without a matching
-- theme_overrides entry below. Keep the three names in sync.
config.key_tables = {
  close_tab_mode = {
    { key = "Enter", mods = "NONE", action = wezterm.action.CloseCurrentTab { confirm = true } },
    { key = "Escape", mods = "NONE", action = wezterm.action.PopKeyTable },
  },
}

-- Network throughput (rx/tx rate) read from /proc/net/dev. tabline concatenates
-- component results without guarding nil, so this must always return a string.
local net_state = nil

local function fmt_rate(bps)
  if bps < 1024 then
    return string.format("%.0f B/s", bps)
  end
  local units = { "KB/s", "MB/s", "GB/s" }
  local value = bps / 1024
  local i = 1
  while value >= 1024 and i < #units do
    value = value / 1024
    i = i + 1
  end
  return string.format("%.1f %s", value, units[i])
end

local function network(_window)
  local file = io.open("/proc/net/dev")
  if not file then
    return "n/a"
  end
  local data = file:read("a")
  file:close()
  if not data then
    return "n/a"
  end
  local rx, tx = 0, 0
  for line in data:gmatch("[^\n]+") do
    local iface, rest = line:match("^%s*([^:%s]+):(.+)$")
    if iface and iface ~= "lo" and not rest:match("^%d+:") then
      local n, line_rx, line_tx = 0, 0, 0
      for num in rest:gmatch("%d+") do
        n = n + 1
        if n == 1 then
          line_rx = tonumber(num)
        elseif n == 9 then
          line_tx = tonumber(num)
        end
      end
      if n >= 10 then
        rx = rx + line_rx
        tx = tx + line_tx
      end
    end
  end
  local now = os.time()
  if not net_state then
    net_state = { rx = rx, tx = tx, t = now, text = " -- " }
    return net_state.text
  end
  if now <= net_state.t then
    return net_state.text
  end
  local dt = math.max(1, now - net_state.t)
  -- dt >= 1 (zero/negative clock steps return cached text; dt clamped anyway);
  -- rate deltas clamped to 0 for counter resets / NIC removal.
  local text = string.format(
    " ↓ %s ↑ %s ",
    fmt_rate(math.max(0, rx - net_state.rx) / dt),
    fmt_rate(math.max(0, tx - net_state.tx) / dt)
  )
  net_state = { rx = rx, tx = tx, t = now, text = text }
  return text
end

-- Close-tab button for the ACTIVE tab. Click arms the close_tab_mode keytable
-- (mode chip turns red); Enter confirms via dialog, Esc/timeout cancels. No
-- one-click close by design. tabline concatenates component results without
-- guarding nil, so this must return a string on every path (see network note).
local function close_button(tab)
  if not tab.is_active then
    return ""
  end
  local glyph = "✕" -- plain U+2715; MesloLGS Nerd Font fallback exists, swap to
                    -- wezterm.nerdfonts.md_close if this renders thin at 16pt
  return wezterm.format({
    { Foreground = { Color = "#f7768e" } }, -- Tokyo Night red (hardcoded like
                                            -- color_scheme above; revisit on theme change)
    { Text = " " .. glyph .. " ", OnClick = { ActivateKeyTable = {
      name = "close_tab_mode", one_shot = true, timeout_milliseconds = 4000,
      clear_stack = true } } },
    { Foreground = { Color = "#c0caf5" } }, -- restore Tokyo Night fg before the
                                            -- separator (belt-and-braces; tabs.lua
                                            -- re-sets colors anyway)
  })
end

tabline.setup({
  options = {
    theme = "Tokyo Night",
    -- Required by the close_tab_mode keytable name ending in _mode (see the
    -- key_tables block); provides the red "armed" chip via the mode component.
    theme_overrides = {
      close_tab_mode = {
        a = { fg = "#1a1b26", bg = "#f7768e" },
        b = { fg = "#f7768e", bg = "#24283b" },
        c = { fg = "#c0caf5", bg = "#1f2335" },
      },
    },
  },
  sections = {
    tabline_a = { "mode" },
    tabline_b = { "cpu", "ram", "battery", network },
    tabline_c = { " " },
    tab_active = {
      "index",
      { "cwd", padding = { left = 0, right = 1 } },
      { "zoomed", padding = 0 },
      close_button,
    },
    tab_inactive = { "index", { "process", padding = { left = 0, right = 1 } } },
    -- clear tabline's right-side defaults (they duplicate ram/cpu/battery);
    -- datetime is re-added on the far right as a live clock (tabline sets
    -- status_update_interval = 500, so it re-renders every ~0.5s)
    tabline_x = {},
    tabline_y = {},
    tabline_z = { { "datetime", style = "%a %d %b %Y %H:%M:%S" } },
  },
  extensions = {},
})

tabline.apply_to_config(config)

-- tabline.apply_to_config zeroes window_padding; restore our padding afterwards.
config.window_padding = { left = 10, right = 10, top = 8, bottom = 8 }

return config
