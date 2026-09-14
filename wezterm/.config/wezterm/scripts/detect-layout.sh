#!/usr/bin/env bash
# Detect current keyboard layout, print EN/TH. Exit 2 + UNKNOWN if indeterminable.
set -uo pipefail

normalize() {
  local s="${1:-}"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  case "$s" in
    *thai*|*" th "*|*"(th)"*|*"+th"*|*",th"*|*"th,"*|*"'th'"*|*'"th"'*|*"[th"*|*" th"*)
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
    *com.apple.keylayout.abc*|*abc*) printf '%s' "$s" | grep -Eq 'abc|us|english' && return 0 ;;
  esac
  printf '%s' "$s" | grep -Eq 'us|english|xkb:us|us\+|us,|\(us\)' && return 0
  return 1
}

# 0. macOS (Darwin): macism -> im-select -> defaults HIToolbox
if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
  if command -v macism >/dev/null 2>&1; then
    raw="$(macism 2>/dev/null || true)"
    if [[ -n "$raw" ]]; then
      if normalize "$raw" >/dev/null; then printf 'TH\n'; exit 0; fi
      if is_english "$raw"; then printf 'EN\n'; exit 0; fi
    fi
  fi
  if command -v im-select >/dev/null 2>&1; then
    raw="$(im-select 2>/dev/null || true)"
    if [[ -n "$raw" ]]; then
      if normalize "$raw" >/dev/null; then printf 'TH\n'; exit 0; fi
      if is_english "$raw"; then printf 'EN\n'; exit 0; fi
    fi
  fi
  raw="$(defaults read com.apple.HIToolbox AppleSelectedInputSources 2>/dev/null || true)"
  if [[ -n "$raw" ]]; then
    if normalize "$raw" >/dev/null; then printf 'TH\n'; exit 0; fi
    if is_english "$raw"; then printf 'EN\n'; exit 0; fi
  fi
  printf 'UNKNOWN\n'
  exit 2
fi

# 1. gsettings current index + sources list
if command -v gsettings >/dev/null 2>&1; then
  current="$(gsettings get org.gnome.desktop.input-sources current 2>/dev/null || true)"
  sources="$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || true)"
  mru="$(gsettings get org.gnome.desktop.input-sources mru-sources 2>/dev/null || true)"
  idx="$(printf '%s' "$current" | grep -Eo '[0-9]+' | head -n1 || true)"
  if [[ -n "${idx:-}" && -n "${sources:-}" ]]; then
    entry="$(printf '%s' "$sources" | tr ',' '\n' | sed -n "$((idx + 1))p" || true)"
    if normalize "$entry" >/dev/null; then printf 'TH\n'; exit 0; fi
    if is_english "$entry"; then printf 'EN\n'; exit 0; fi
  fi
  # Fallback: first mru entry order decides
  if [[ -n "${mru:-}" ]]; then
    if normalize "$mru" >/dev/null; then
      # mru lists most-recent first; but bare substring could mislead, check order
      us_pos="${mru%%us*}"; th_pos="${mru%%th*}"
      if [[ "$mru" != *"us"* ]] || (( ${#th_pos} < ${#us_pos} )); then printf 'TH\n'; exit 0; fi
      printf 'EN\n'; exit 0
    elif is_english "$mru"; then
      printf 'EN\n'; exit 0
    fi
  fi
fi

# 2. ibus engine
if command -v ibus >/dev/null 2>&1; then
  engine="$(ibus engine 2>/dev/null || true)"
  if [[ -n "$engine" ]]; then
    if normalize "$engine" >/dev/null; then printf 'TH\n'; exit 0; fi
    if is_english "$engine" || [[ "$engine" == *xkb* ]]; then printf 'EN\n'; exit 0; fi
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
