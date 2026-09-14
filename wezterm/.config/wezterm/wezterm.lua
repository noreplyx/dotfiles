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

local kb_layout_state = { text = " -- " }
local kb_cache_primary = (os.getenv("HOME") or "") .. "/.cache/wezterm-kb-layout"
local kb_cache_fallback = (os.getenv("XDG_RUNTIME_DIR") or "") .. "/wezterm-kb-layout"
local kb_cache_path = kb_cache_primary
if kb_cache_primary == "/.cache/wezterm-kb-layout" then
  kb_cache_path = kb_cache_fallback
end

local function kb_pad(code)
  code = code:upper():sub(1, 2)
  return " " .. code .. " "
end

local function kb_format(code)
  if code == "TH" then
    return wezterm.format({
      { Foreground = { Color = "#7dcfff" } },
      { Text = kb_pad(code) },
    })
  end
  return wezterm.format({ { Text = kb_pad(code) } })
end

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
  -- Keyboard layout toggle: CTRL+SHIFT+SPACE primary, ALT+SHIFT+L fallback.
  -- No collision with existing CTRL|SHIFT h/j/k/l/d/r/w/t or ALT+Enter.
  { key = " ", mods = "CTRL|SHIFT", action = wezterm.action.EmitEvent "kb-toggle-layout" },
  { key = "L", mods = "ALT|SHIFT", action = wezterm.action.EmitEvent "kb-toggle-layout" },
}

local kb_toggle_script = (os.getenv("HOME") or "") .. "/.config/wezterm/scripts/toggle-layout.sh"

wezterm.on("kb-toggle-layout", function(window, _pane)
  -- Instant path: flip Lua state + toast FIRST (keypress→pixels, no waits),
  -- force an immediate status re-render, then hand the explicit target to
  -- toggle-layout.sh LAST (fire-and-forget). Explicit EN/TH avoids the
  -- stale-EN race where --toggle re-detects the pre-switch layout and flips
  -- back. Background script heals cache/OSC.
  local before = kb_layout_state.text:match("%a%a") or "??"
  local after = "TH"
  if before == "TH" then
    after = "EN"
  elseif before == "EN" then
    after = "TH"
  end
  kb_layout_state.text = kb_pad(after)
  if window then
    pcall(function() window:toast_notification("Keyboard layout", before .. " → " .. after, nil, 1500) end)
    -- Nudge tabline to re-render now instead of waiting for its ~1s
    -- status_update_interval tick; harmless no-op if unsupported.
    pcall(function() window:set_config_overrides(window:get_config_overrides() or {}) end)
  end
  pcall(function()
    wezterm.run_child_process({ "bash", kb_toggle_script, after })
  end)
end)

wezterm.on("gui-startup", function()
  pcall(function()
    wezterm.run_child_process({ "bash", "-lc",
      "pgrep -f kb-layout-watch.sh >/dev/null || (nohup ~/.config/wezterm/scripts/kb-layout-watch.sh >/dev/null 2>&1 &)" })
  end)
end)

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
-- component results without guarding nil, so this must always return
-- wezterm.format cells (never nil).
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
    return wezterm.format({ { Text = "n/a" } })
  end
  local data = file:read("a")
  file:close()
  if not data then
    return wezterm.format({ { Text = "n/a" } })
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
    return wezterm.format({ { Text = net_state.text } })
  end
  if now <= net_state.t then
    return wezterm.format({ { Text = net_state.text } })
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
  return wezterm.format({ { Text = text } })
end

-- Close-tab button for the ACTIVE tab. Click arms the close_tab_mode keytable
-- (mode chip turns red); Enter confirms via dialog, Esc/timeout cancels. No
-- one-click close by design. tabline concatenates component results without
-- guarding nil, so this must return wezterm.format cells on every path (see network note).
local function close_button(tab)
  if not tab.is_active then
    return wezterm.format({ { Text = "" } })
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

-- _window is the tabline component signature (window, tab). File cache first:
-- the watch daemon owns cache writes on every external switch (~0.15s) but
-- emits no OSC (no tty), while user_vars.KB goes stale mid-line (precmd only
-- re-emits on Enter). Push-first ordering let a stale EN user_var shadow a
-- fresh TH cache file, sticking on EN until the next prompt. Cache-first
-- heals within one 1s tick; user_vars stays the fallback/nudge path.
-- Keeps last-known-good (initial " -- ", never a fake default). Always
-- returns wezterm.format cells; tabline concatenates without nil guards.
local function kb_layout(window)
  local file = io.open(kb_cache_path, "r")
  if not file and kb_cache_path ~= kb_cache_fallback then
    file = io.open(kb_cache_fallback, "r")
  end
  if not file then
    file = io.open((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/wezterm-kb-layout", "r")
  end
  if not file then
    file = io.open("/tmp/wezterm-kb-layout", "r")
  end
  if file then
    local raw = file:read("*l")
    file:close()
    local code = raw and raw:match("^%s*(%a%a)%s*$")
    if code then
      code = code:upper()
      if code == "EN" or code == "TH" then
        kb_layout_state.text = kb_pad(code)
        return kb_format(code)
      end
    end
  end
  if window then
    local ok, vars = pcall(function() return window:user_vars() end)
    if ok and vars and vars.KB then
      local code = tostring(vars.KB):match("^%s*(%a%a)%s*$")
      if code then
        code = code:upper()
        if code == "EN" or code == "TH" then
          kb_layout_state.text = kb_pad(code)
          return kb_format(code)
        end
      end
    end
  end
  local last = kb_layout_state.text:match("%a%a")
  if last == "TH" or last == "EN" then
    return kb_format(last)
  end
  return wezterm.format({ { Text = kb_layout_state.text } })
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
    -- status_update_interval = 1, so it re-renders every ~1s)
    tabline_x = {},
    tabline_y = { kb_layout },
    tabline_z = { { "datetime", style = "%a %d %b %Y %H:%M:%S" } },
  },
})

tabline.apply_to_config(config)

-- Force frequent re-render so kb_layout (fresh file read every call, no
-- stale upvalue) reflects cache changes within ~1s. tabline sets this
-- itself, but re-assert after apply_to_config in case of version drift.
-- NOTE: must stay an integer number of seconds; fractional values (e.g. 0.5)
-- are rejected by config validation on some wezterm versions.
config.status_update_interval = 1

-- Push path: zsh emits OSC 1337 SetUserVar KB=<EN|TH> on every switch.
-- This event fires instantly (even mid-line); update last-good state here
-- and nudge tabline to re-render now instead of waiting for the next tick.
-- NOTE: event name is literally "user-var-changed" (lowercase, hyphens);
-- "KB" (uppercase) is the variable name inside the handler.
-- The handler NEVER writes the cache file: the watch daemon + toggle script
-- own cache writes from live gsettings detection. A stale EN user_var
-- (precmd re-emit from before a mid-line Super+Space switch) must not
-- clobber a fresh TH cache file via write-through.
wezterm.on("user-var-changed", function(window, _pane, name, value)
  if name ~= "KB" then
    return
  end
  local code = tostring(value or ""):match("^%s*(%a%a)%s*$")
  if code then
    code = code:upper()
    if code == "EN" or code == "TH" then
      kb_layout_state.text = kb_pad(code)
    end
  end
  if window then
    pcall(function() window:set_config_overrides(window:get_config_overrides() or {}) end)
  end
end)

-- tabline.apply_to_config zeroes window_padding; restore our padding afterwards.
config.window_padding = { left = 10, right = 10, top = 8, bottom = 8 }

return config
