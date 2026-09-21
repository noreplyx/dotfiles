#!/usr/bin/env bash
# Detect current keyboard layout, print EN/TH. Exit 2 + UNKNOWN if indeterminable.
set -uo pipefail
_OS="$(uname -s 2>/dev/null || true)"
_KB_DIR="${XDG_RUNTIME_DIR:-/tmp}"
if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "${HOME}/.cache" ]]; then _KB_DIR="${HOME}/.cache"; fi
_SEL_CACHE="${_KB_DIR}/wezterm-kb-selector"
_dbg() { [[ "${KB_DEBUG:-0}" == "1" ]] && printf 'detect: %s\n' "$*" >&2 || true; }

# Darwin exact-match classifier: runs before fuzzy normalize/is_english so
# native input-source IDs never fall through to substring guessing.
_darwin_exact() {
  local s="${1:-}" t=""
  t="$(printf '%s' "$s" | tr -d ' \t\r\n' || true)"
  case "$t" in
    com.apple.keylayout.ABC|com.apple.keylayout.US|ABC|US) printf 'EN\n'; return 0 ;;
    com.apple.keylayout.Thai|com.apple.keylayout.ThaiKedmanee|Thai) printf 'TH\n'; return 0 ;;
  esac
  return 1
}

_cached_sel() {
  local s="${IM_SELECTOR:-}"
  if [[ -z "$s" && -r "$_SEL_CACHE" ]]; then
    s="$(cat "$_SEL_CACHE" 2>/dev/null | tr -d ' \t\r\n' || true)"
  fi
  case "${s##*/}" in macism|im-select) printf '%s' "${s##*/}" ;; *) printf '' ;; esac
}

_try_sel() {
  local sel="$1" raw="" code=""
  [[ -z "$sel" ]] && return 1
  command -v "$sel" >/dev/null 2>&1 || return 1
  raw="$("$sel" 2>/dev/null || true)"
  _dbg "sel=$sel raw=${raw:-<empty>}"
  [[ -z "$raw" ]] && return 1
  if code="$(_darwin_exact "$raw")" && [[ -n "$code" ]]; then printf '%s\n' "$code"; return 0; fi
  if normalize "$raw" >/dev/null; then printf 'TH\n'; return 0; fi
  if is_english "$raw"; then printf 'EN\n'; return 0; fi
  return 1
}

normalize() {
  local s="${1:-}"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  case "$s" in
    *thai*|*tha*|*" th "*|*"(th)"*|*"+th"*|*",th"*|*"th,"*|*"'th'"*|*'"th"'*|*"[th"*|*" th"*)
      printf 'TH\n'; return 0 ;;
  esac
  # Bare "th" token as its own word
  if printf '%s' "$s" | grep -Eq '(^|[^a-z])th([^a-z]|$)'; then
    printf 'TH\n'; return 0
  fi
  return 1
}

is_english() {
  local s="${1:-}"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  case "$s" in
    *usinternational*|*us_international*|*us-international*) return 0 ;;
  esac
  printf '%s' "$s" | grep -Eq '(^|[^a-z])(us|english|abc)([^a-z]|$)' && return 0
  return 1
}

# sources entries are tuples like ('xkb', 'us'); splitting on ',' breaks
# them, so extract whole tuples and index 0-based.
_sources_entry() {
  local sources="$1" idx="$2"
  printf '%s' "$sources" | grep -Eo "\('[^']*', *'[^']*'\)" | sed -n "$((idx + 1))p" || true
}

# Fast path: FAST=1 serves live ibus engine first (authoritative for
# Win+Space/Super+Space switches; gsettings `current` goes stale at 0),
# then mru-sources recency, then current+sources, then cache + cheap backends.
# Else UNKNOWN exit 2.
if [[ "${FAST:-0}" == "1" ]]; then
  if command -v ibus >/dev/null 2>&1; then
    engine="$(ibus engine 2>/dev/null || true)"
    if [[ -n "${engine:-}" ]]; then
      if normalize "$engine" >/dev/null; then printf 'TH\n'; exit 0; fi
      if is_english "$engine" || [[ "$engine" == *xkb* ]]; then printf 'EN\n'; exit 0; fi
    fi
  fi
  if [[ "$_OS" != "Darwin" ]] && command -v gsettings >/dev/null 2>&1; then
    mru="$(gsettings get org.gnome.desktop.input-sources mru-sources 2>/dev/null || true)"
    if [[ -n "${mru:-}" ]]; then
      _mru_first="$(printf '%s' "$mru" | grep -Eo "\('[^']*', *'[^']*'\)" | head -n1 || true)"
      [[ -z "$_mru_first" ]] && _mru_first="$mru"
      if normalize "$_mru_first" >/dev/null; then printf 'TH\n'; exit 0; fi
      if is_english "$_mru_first" >/dev/null; then printf 'EN\n'; exit 0; fi
    fi
    current="$(gsettings get org.gnome.desktop.input-sources current 2>/dev/null || true)"
    sources="$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || true)"
    idx="$(printf '%s' "$current" | grep -Eo '[0-9]+' | tail -n1 || true)"
    if [[ -n "${idx:-}" && -n "${sources:-}" ]]; then
      entry="$(_sources_entry "$sources" "$idx")"
      if normalize "$entry" >/dev/null; then printf 'TH\n'; exit 0; fi
      if is_english "$entry" >/dev/null; then printf 'EN\n'; exit 0; fi
    fi
  fi
  _fast_cache="${XDG_RUNTIME_DIR:-/tmp}/wezterm-kb-layout"
  if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "${HOME}/.cache" ]]; then _fast_cache="${HOME}/.cache/wezterm-kb-layout"; fi
  if [[ -r "$_fast_cache" ]]; then
    _c="$(cat "$_fast_cache" 2>/dev/null | tr -d ' \t\r\n' || true)"
    case "$_c" in
      EN|en|En|TH|th|Th) printf '%s\n' "$_c" | tr '[:lower:]' '[:upper:]'; exit 0 ;;
    esac
  fi
  if [[ "$_OS" == "Darwin" ]]; then
    _cs="$(_cached_sel)"
    if [[ -n "$_cs" ]]; then
      if _try_sel "$_cs"; then exit 0; fi
    fi
    if command -v macism >/dev/null 2>&1; then
      raw="$(macism 2>/dev/null || true)"
      if [[ -n "$raw" ]]; then
        if code="$(_darwin_exact "$raw")" && [[ -n "$code" ]]; then printf '%s\n' "$code"; exit 0; fi
        if normalize "$raw" >/dev/null; then printf 'TH\n'; exit 0; fi
        if is_english "$raw"; then printf 'EN\n'; exit 0; fi
      fi
    fi
    if command -v im-select >/dev/null 2>&1; then
      raw="$(im-select 2>/dev/null || true)"
      if [[ -n "$raw" ]]; then
        if code="$(_darwin_exact "$raw")" && [[ -n "$code" ]]; then printf '%s\n' "$code"; exit 0; fi
        if normalize "$raw" >/dev/null; then printf 'TH\n'; exit 0; fi
        if is_english "$raw"; then printf 'EN\n'; exit 0; fi
      fi
    fi
    printf 'UNKNOWN\n'; exit 2
  fi
  if command -v gsettings >/dev/null 2>&1; then
    mru="$(gsettings get org.gnome.desktop.input-sources mru-sources 2>/dev/null || true)"
    if [[ -n "${mru:-}" ]]; then
      _mru_first="$(printf '%s' "$mru" | grep -Eo "\('[^']*', *'[^']*'\)" | head -n1 || true)"
      [[ -z "$_mru_first" ]] && _mru_first="$mru"
      if normalize "$_mru_first" >/dev/null; then printf 'TH\n'; exit 0; fi
      if is_english "$_mru_first" >/dev/null; then printf 'EN\n'; exit 0; fi
    fi
  fi
  printf 'UNKNOWN\n'; exit 2
fi

# 0. macOS (Darwin): macism -> im-select -> defaults HIToolbox
if [[ "$_OS" == "Darwin" ]]; then
  _cs="$(_cached_sel)"
  if [[ -n "$_cs" ]]; then
    if _try_sel "$_cs"; then exit 0; fi
  fi
  if command -v macism >/dev/null 2>&1; then
    raw="$(macism 2>/dev/null || true)"
    _dbg "macism raw=${raw:-<empty>}"
    if [[ -n "$raw" ]]; then
      if code="$(_darwin_exact "$raw")" && [[ -n "$code" ]]; then printf '%s\n' "$code"; exit 0; fi
      if normalize "$raw" >/dev/null; then printf 'TH\n'; exit 0; fi
      if is_english "$raw"; then printf 'EN\n'; exit 0; fi
    fi
  fi
  if command -v im-select >/dev/null 2>&1; then
    raw="$(im-select 2>/dev/null || true)"
    _dbg "im-select raw=${raw:-<empty>}"
    if [[ -n "$raw" ]]; then
      if code="$(_darwin_exact "$raw")" && [[ -n "$code" ]]; then printf '%s\n' "$code"; exit 0; fi
      if normalize "$raw" >/dev/null; then printf 'TH\n'; exit 0; fi
      if is_english "$raw"; then printf 'EN\n'; exit 0; fi
    fi
  fi
  raw=""
  # Read-only detect defaults to ON; opt out with KB_ALLOW_DEFAULTS=0.
  # FAST path above always skips defaults (CPU).
  if [[ "${KB_ALLOW_DEFAULTS:-1}" == "1" ]]; then
    raw="$(defaults read com.apple.HIToolbox AppleSelectedInputSources 2>/dev/null || true)"
  fi
  _dbg "defaults raw=${raw:-<empty>}"
  if [[ -n "$raw" ]]; then
    if code="$(_darwin_exact "$raw")" && [[ -n "$code" ]]; then printf '%s\n' "$code"; exit 0; fi
    if normalize "$raw" >/dev/null; then printf 'TH\n'; exit 0; fi
    if is_english "$raw"; then printf 'EN\n'; exit 0; fi
  fi
  printf 'UNKNOWN\n'
  exit 2
fi

# 1. ibus engine (live; authoritative for Win+Space/Super+Space switches)
if command -v ibus >/dev/null 2>&1; then
  engine="$(ibus engine 2>/dev/null || true)"
  if [[ -n "$engine" ]]; then
    if normalize "$engine" >/dev/null; then printf 'TH\n'; exit 0; fi
    if is_english "$engine" || [[ "$engine" == *xkb* ]]; then printf 'EN\n'; exit 0; fi
  fi
fi

# 2. gsettings mru-sources recency, then current index + sources list
if command -v gsettings >/dev/null 2>&1; then
  current="$(gsettings get org.gnome.desktop.input-sources current 2>/dev/null || true)"
  sources="$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || true)"
  mru="$(gsettings get org.gnome.desktop.input-sources mru-sources 2>/dev/null || true)"
  # Recency first: mru[0] tracks the last-used source even when `current` is stale
  if [[ -n "${mru:-}" ]]; then
    _mru_first="$(printf '%s' "$mru" | grep -Eo "\('[^']*', *'[^']*'\)" | head -n1 || true)"
    [[ -z "$_mru_first" ]] && _mru_first="$mru"
    if normalize "$_mru_first" >/dev/null; then printf 'TH\n'; exit 0; fi
    if is_english "$_mru_first"; then printf 'EN\n'; exit 0; fi
  fi
  idx="$(printf '%s' "$current" | grep -Eo '[0-9]+' | tail -n1 || true)"
  if [[ -n "${idx:-}" && -n "${sources:-}" ]]; then
    entry="$(_sources_entry "$sources" "$idx")"
    if normalize "$entry" >/dev/null; then printf 'TH\n'; exit 0; fi
    if is_english "$entry"; then printf 'EN\n'; exit 0; fi
  fi
fi

# 3. hyprctl devices keyboards layout
if command -v hyprctl >/dev/null 2>&1; then
  out="$(hyprctl devices -j 2>/dev/null || hyprctl devices 2>/dev/null || true)"
  if [[ -n "$out" ]]; then
    active="$(printf '%s' "$out" | grep -Eo '"active_keymap": *"[^"]+"' | head -n1 || true)"
    [[ -z "$active" ]] && active="$(printf '%s' "$out" | grep -Ei 'active.*keymap|layout' | head -n1 || true)"
    if [[ -n "$active" ]]; then
      if normalize "$active" >/dev/null; then printf 'TH\n'; exit 0; fi
      if is_english "$active"; then printf 'EN\n'; exit 0; fi
    fi
  fi
fi

# 4. fcitx5-remote
if command -v fcitx5-remote >/dev/null 2>&1; then
  name="$(fcitx5-remote -n 2>/dev/null || true)"
  if [[ -n "$name" ]]; then
    if normalize "$name" >/dev/null; then printf 'TH\n'; exit 0; fi
    if is_english "$name" || [[ "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" == *keyboard-us* ]]; then
      printf 'EN\n'; exit 0
    fi
  fi
fi

# 5. setxkbmap query
if command -v setxkbmap >/dev/null 2>&1; then
  q="$(setxkbmap -query 2>/dev/null || true)"
  if [[ -n "$q" ]]; then
    layout="$(printf '%s' "$q" | awk '/layout/{print $2}' || true)"
    if [[ -n "$layout" ]]; then
      first="${layout%%,*}"
      if normalize "$first" >/dev/null; then printf 'TH\n'; exit 0; fi
      printf '%s\n' "$first" | grep -Eq '^[A-Za-z]{2}$' && { printf '%s\n' "$first" | tr '[:lower:]' '[:upper:]'; exit 0; }
      if is_english "$first"; then printf 'EN\n'; exit 0; fi
    fi
  fi
fi

printf 'UNKNOWN\n'
exit 2
