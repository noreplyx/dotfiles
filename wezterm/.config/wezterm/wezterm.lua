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

local is_windows = (wezterm.target_triple and wezterm.target_triple:find("windows")) ~= nil

-- Detect whether a hardware GPU adapter is available, or if Windows fell back
-- to CPU rendering ("Microsoft Basic Render Driver", device_type == "Cpu").
local has_hardware_gpu = true
if wezterm.gui and wezterm.gui.enumerate_gpus then
  local ok, gpus = pcall(wezterm.gui.enumerate_gpus)
  if ok and type(gpus) == "table" and #gpus > 0 then
    has_hardware_gpu = false
    for _, gpu in ipairs(gpus) do
      if gpu.device_type ~= "Cpu" then
        has_hardware_gpu = true
        break
      end
    end
  end
end

-- Use zsh login shell on Unix; on Windows fall back to system default (pwsh/powershell)
-- so wezterm doesn't try to run /bin/zsh which doesn't exist there.
if not is_windows then
  -- Prefer zsh from PATH; hardcoding /bin/zsh breaks on macOS (Homebrew zsh) and NixOS.
  config.default_prog = { "zsh", "-l" }
else
  config.default_prog = { "pwsh.exe", "-NoLogo" }
  -- Windows often lacks a modern OpenGL driver (e.g. GDI Generic 1.1 in VMs/RDP
  -- or when the display driver has crashed), causing:
  --   "The OpenGL implementation is too old to work with glium"
  -- WebGpu uses DirectX 12 / WARP on Windows and works reliably.
  config.front_end = "WebGpu"
  config.webgpu_power_preference = "HighPerformance"
end
config.set_environment_variables = {
  XDG_CONFIG_HOME = wezterm.home_dir .. "/.config",
}
config.color_scheme = "Tokyo Night"
config.font = wezterm.font_with_fallback(
  { "JetBrains Mono", "MesloLGS Nerd Font Mono" },
  { harfbuzz_features = { "calt=0", "clig=0", "liga=0" } }
)
config.font_size = 16.0
config.window_background_opacity = is_windows and 1.0 or (has_hardware_gpu and 0.96 or 1.0)
if has_hardware_gpu then
  config.max_fps = 120
  config.animation_fps = 60
  config.cursor_blink_rate = 0
else
  config.max_fps = 60
  config.animation_fps = 1
  config.cursor_blink_rate = 0
end
config.window_padding = {
  left = 10,
  right = 10,
  top = 8,
  bottom = 8,
}
config.use_fancy_tab_bar = false
config.scrollback_lines = 10000
config.check_for_updates = false
config.enable_scroll_bar = false
config.adjust_window_size_when_changing_font_size = false

local keyboard_layout_state = { text = " -- ", initialized = false }
local last_keyboard_cache_read_epoch = 0
local keyboard_layout_cache_paths = {}
if not is_windows then
  local seen = {}
  local home = os.getenv("HOME")
  local xdg_runtime = os.getenv("XDG_RUNTIME_DIR")
  for _, candidate in ipairs({
    (xdg_runtime and xdg_runtime ~= "") and (xdg_runtime .. "/wezterm-kb-layout") or false,
    (home and home ~= "") and (home .. "/.cache/wezterm-kb-layout") or false,
    "/tmp/wezterm-kb-layout",
  }) do
    if candidate and not seen[candidate] then
      seen[candidate] = true
      table.insert(keyboard_layout_cache_paths, candidate)
    end
  end
end

local function pad_keyboard_layout(code)
  code = code:upper():sub(1, 2)
  return " " .. code .. " "
end

local function format_keyboard_layout(code)
  if code == "TH" then
    return wezterm.format({
      { Foreground = { Color = "#7dcfff" } },
      { Text = pad_keyboard_layout(code) },
      { Foreground = { Color = "#c0caf5" } },
    })
  end
  return wezterm.format({ { Text = pad_keyboard_layout(code) } })
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

local keyboard_layout_toggle_script = (os.getenv("HOME") or "") .. "/.config/wezterm/scripts/toggle-layout.sh"
local keyboard_layout_watch_script = (os.getenv("HOME") or "") .. "/.config/wezterm/scripts/kb-layout-watch.sh"

wezterm.on("kb-toggle-layout", function(window, _pane)
  if is_windows then
    return
  end
  -- Instant path: flip Lua state + toast FIRST (keypress→pixels, no waits),
  -- force an immediate status re-render, then hand the explicit target to
  -- toggle-layout.sh LAST (fire-and-forget). Explicit EN/TH avoids the
  -- stale-EN race where --toggle re-detects the pre-switch layout and flips
  -- back. Background script heals cache/OSC.
  local before = keyboard_layout_state.text:match("%a%a") or "??"
  local after = "TH"
  if before == "TH" then
    after = "EN"
  elseif before == "EN" then
    after = "TH"
  end
  keyboard_layout_state.text = pad_keyboard_layout(after)
  keyboard_layout_state.initialized = true
  last_keyboard_cache_read_epoch = os.time()
  if window then
    pcall(function() window:toast_notification("Keyboard layout", before .. " → " .. after, nil, 1500) end)
    -- Nudge tabline to re-render now instead of waiting for its ~1s
    -- status_update_interval tick; harmless no-op if unsupported.
    pcall(function() window:set_config_overrides(window:get_config_overrides() or {}) end)
  end
  pcall(function()
    wezterm.run_child_process({ "bash", keyboard_layout_toggle_script, after })
  end)
end)

wezterm.on("gui-startup", function()
  if is_windows then
    return
  end
  pcall(function()
    wezterm.run_child_process({ "bash", "-lc",
      'command -v pgrep >/dev/null 2>&1 && pgrep -f "kb-layout-watch\\.sh" >/dev/null 2>&1 || nohup "' .. keyboard_layout_watch_script .. '" >/dev/null 2>&1 &' })
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

-- Close-tab button for the ACTIVE tab. Click arms the close_tab_mode keytable
-- (mode chip turns red); Enter confirms via dialog, Esc/timeout cancels. No
-- one-click close by design. tabline concatenates component results without
-- guarding nil, so this must return wezterm.format cells on every path.
local function close_button(tab)
  if not tab.is_active then
    return wezterm.format({ { Text = "" } })
  end
  local glyph = "✕" -- plain U+2715; MesloLGS Nerd Font fallback exists, swap to
                    -- wezterm.nerdfonts.md_close if this renders thin at 16pt
  local ok, formatted = pcall(wezterm.format, {
    { Foreground = { Color = "#f7768e" } }, -- Tokyo Night red (hardcoded like
                                            -- color_scheme above; revisit on theme change)
    { Text = " " .. glyph .. " ", OnClick = { ActivateKeyTable = {
      name = "close_tab_mode", one_shot = true, timeout_milliseconds = 4000,
      clear_stack = true } } },
    { Foreground = { Color = "#c0caf5" } }, -- restore Tokyo Night fg before the
                                            -- separator (belt-and-braces; tabs.lua
                                            -- re-sets colors anyway)
  })
  if ok then
    return formatted
  end
  return wezterm.format({
    { Foreground = { Color = "#f7768e" } },
    { Text = " " .. glyph .. " " },
    { Foreground = { Color = "#c0caf5" } },
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
local function render_keyboard_layout(window)
  if is_windows then
    local ok, vars = pcall(function() return window and window:user_vars() end)
    local raw_layout = ok and vars and vars.KB
    local code = raw_layout and tostring(raw_layout):match("^%s*(%a%a)%s*$")
    if code then
      return format_keyboard_layout(code:upper())
    end
    return format_keyboard_layout("EN")
  end
  local now = os.time()
  if now - last_keyboard_cache_read_epoch >= 5 then
    last_keyboard_cache_read_epoch = now
    for _, path in ipairs(keyboard_layout_cache_paths) do
      local file = io.open(path, "r")
      if file then
        local raw_layout = file:read("*l")
        file:close()
        local code = raw_layout and raw_layout:match("^%s*(%a%a)%s*$")
        if code then
          code = code:upper()
          if code == "EN" or code == "TH" then
            keyboard_layout_state.text = pad_keyboard_layout(code)
            keyboard_layout_state.initialized = true
            return format_keyboard_layout(code)
          end
        end
      end
    end
  end
  if not keyboard_layout_state.initialized and window then
    local ok, vars = pcall(function() return window:user_vars() end)
    if ok and vars and vars.KB then
      local code = tostring(vars.KB):match("^%s*(%a%a)%s*$")
      if code then
        code = code:upper()
        if code == "EN" or code == "TH" then
          keyboard_layout_state.text = pad_keyboard_layout(code)
          keyboard_layout_state.initialized = true
          return format_keyboard_layout(code)
        end
      end
    end
  end
  local last = keyboard_layout_state.text:match("%a%a")
  if last == "TH" or last == "EN" then
    return format_keyboard_layout(last)
  end
  return wezterm.format({ { Text = keyboard_layout_state.text } })
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
    -- On Windows 11, tabline.wez's "cpu" and "ram" spawn `cmd.exe /C wmic ...`
    -- synchronously on the UI thread; wmic is removed in Win11 so each call
    -- fails after ~200ms without updating last_update_time (never throttling).
    tabline_b = is_windows and {} or { "battery" },
    tabline_c = { " " },
    tab_active = {
      "index",
      { "cwd", padding = { left = 0, right = 1 } },
      { "zoomed", padding = 0 },
      close_button,
    },
    tab_inactive = { "index", { "process", padding = { left = 0, right = 1 } } },
    -- clear tabline's right-side defaults (they duplicate ram/cpu/battery);
    -- datetime is re-added on the far right as a live clock
    tabline_x = {},
    tabline_y = { render_keyboard_layout },
    tabline_z = { { "datetime", style = "%a %d %b %H:%M" } },
  },
})

tabline.apply_to_config(config)

-- NOTE: status_update_interval is in MILLISECONDS (5000 = 5s); when running on
-- CPU software rendering (no hardware GPU), throttle to 15s to avoid constant
-- full-window CPU redraws.
config.status_update_interval = has_hardware_gpu and 5000 or 15000

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
      keyboard_layout_state.text = pad_keyboard_layout(code)
      keyboard_layout_state.initialized = true
    end
  end
  if window then
    pcall(function() window:set_config_overrides(window:get_config_overrides() or {}) end)
  end
end)

-- tabline.apply_to_config zeroes window_padding; restore our padding afterwards.
config.window_padding = { left = 10, right = 10, top = 8, bottom = 8 }

return config
