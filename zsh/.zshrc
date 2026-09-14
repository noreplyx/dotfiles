# Created by newuser for 5.9

### Added by Zinit's installer
if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
    print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
    command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
    command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" && \
        print -P "%F{33} %F{34}Installation successful.%f%b" || \
        print -P "%F{160} The clone has failed.%f%b"
fi

source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"

autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# Load a few important annexes, without Turbo
# (this is currently required for annexes)
zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust

### End of Zinit's installer chunk

### ===== TURBO MODE PLUGINS =====

# autosuggestions (เดาคำสั่ง)
zinit ice wait"0" lucid atload"_zsh_autosuggest_start"
zinit light zsh-users/zsh-autosuggestions

# completions เพิ่มเติม
zinit ice wait"0" lucid
zinit light zsh-users/zsh-completions

# fzf-tab (Tab UI)
zinit ice wait"0" lucid
zinit light Aloxaf/fzf-tab

# syntax highlight (ต้องท้ายสุด)
zinit ice wait"0"
zinit light zsh-users/zsh-syntax-highlighting

autoload -Uz compinit
compinit -C
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

# local binaries
export PATH="$HOME/.local/bin:$PATH"

# Keyboard layout publisher for wezterm tabline (thin wrapper over detect-layout.sh).
_kb_dir="${XDG_RUNTIME_DIR:-/tmp}"
if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "${HOME}/.cache" ]]; then _kb_dir="${HOME}/.cache"; fi
command mkdir -p "$_kb_dir" 2>/dev/null || { _kb_dir="/tmp"; command mkdir -p "$_kb_dir" 2>/dev/null || true; }
__kb_layout_cache="${_kb_dir}/wezterm-kb-layout"
__kb_detect_script="${HOME}/.config/wezterm/scripts/detect-layout.sh"
__kb_emit_user_var() {
  local code="$1" b64=""
  [[ -n "$code" ]] || return 0
  if command -v base64 >/dev/null 2>&1; then
    b64="$(printf '%s' "$code" | base64 2>/dev/null | tr -d '\n')" || b64=""
  fi
  [[ -n "$b64" ]] || return 0
  printf '\033]1337;SetUserVar=KB=%s\007' "$b64" > /dev/tty 2>/dev/null || true
}
__publish_kb_layout() {
  local code=""
  if [[ -x "$__kb_detect_script" ]]; then
    code="$("$__kb_detect_script" 2>/dev/null || true)"
    [[ "$code" == "UNKNOWN" ]] && code=""
  fi
  if [[ -z "$code" ]]; then
    local raw engine
    raw="$(gsettings get org.gnome.desktop.input-sources mru-sources 2>/dev/null)" || raw=""
    if [[ -n "$raw" ]]; then
      if [[ "$raw" == *"us"* ]]; then
        code="EN"
      fi
      if [[ "$raw" == *"th"* ]]; then
        local us_pos="${raw%%us*}"
        local th_pos="${raw%%th*}"
        if (( ${#th_pos} < ${#us_pos} )) || [[ "$raw" != *"us"* ]]; then
          code="TH"
        else
          code="EN"
        fi
      fi
    fi
    if [[ -z "$code" ]]; then
      engine="$(ibus engine 2>/dev/null)" || engine=""
      case "$engine" in
        *th*) code="TH" ;;
        *us*|*xkb:us*) code="EN" ;;
      esac
    fi
  fi
  [[ "$code" =~ ^[A-Za-z]{2}$ ]] || return 0
  [[ -f "$__kb_layout_cache" && "$(<"$__kb_layout_cache" 2>/dev/null)" == "$code" ]] && { __kb_emit_user_var "$code"; return 0; }
  local tmp
  tmp="$(mktemp "${__kb_layout_cache}.tmp.XXXXXX" 2>/dev/null)" || return 0
  printf '%s' "$code" > "$tmp" 2>/dev/null || return 0
  mv -f "$tmp" "$__kb_layout_cache" 2>/dev/null || rm -f "$tmp"
  __kb_emit_user_var "$code"
}
__kb_last_emitted=""
__kb_precmd_publish_cached() {
  local code=""
  if [[ -r "$__kb_layout_cache" ]]; then
    code="$(<"$__kb_layout_cache" 2>/dev/null)" || code=""
    code="${code//[^A-Za-z]/}"
    [[ ${#code} -eq 2 ]] || return 0
    [[ "$code" == "$__kb_last_emitted" ]] && return 0
    __kb_last_emitted="$code"
    __kb_emit_user_var "$code"
  fi
}
autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook precmd __kb_precmd_publish_cached 2>/dev/null || true
__kb_precmd_publish_cached 2>/dev/null || true
# Live updates while idle (Linux only; Darwin watcher polls): singleton daemon.
# Push paths (watch daemon, toggle script) own detection + cache writes; precmd
# above only re-emits the cache (zero detectors, zero gsettings forks).
if [[ "$(uname -s 2>/dev/null)" != "Darwin" ]] && command -v gsettings >/dev/null 2>&1; then
  if [[ -z "${__kb_layout_monitor_started:-}" ]]; then
    __kb_layout_monitor_started=1
    if ! pgrep -f "kb-layout-watch\.sh" >/dev/null 2>&1 \
      && ! pgrep -f "gsettings monitor.*mru-sources" >/dev/null 2>&1; then
      (nohup "$HOME/.config/wezterm/scripts/kb-layout-watch.sh" >/dev/null 2>&1 &) 2>/dev/null || true
      disown 2>/dev/null || true
    fi
  fi
fi

# Per-machine overrides (gitignored). Put machine-specific PATHs here,
# e.g. flutter, Antigravity CLI, etc.
if [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi
