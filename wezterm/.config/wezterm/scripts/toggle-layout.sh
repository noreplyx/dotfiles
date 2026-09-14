#!/usr/bin/env bash
# Toggle/switch keyboard layout. Usage: toggle-layout.sh [--next|--toggle|EN|TH]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect-layout.sh"
_KB_DIR="${XDG_RUNTIME_DIR:-/tmp}"
if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "${HOME}/.cache" ]]; then _KB_DIR="${HOME}/.cache"; fi
command mkdir -p "$_KB_DIR" 2>/dev/null || { _KB_DIR="/tmp"; command mkdir -p "$_KB_DIR" 2>/dev/null || true; }
CACHE="${_KB_DIR}/wezterm-kb-layout"

target="${1:---toggle}"
case "$target" in
  --next|--toggle|toggle|next) WANT="NEXT" ;;
  EN|en|En) WANT="EN" ;;
  TH|th|Th) WANT="TH" ;;
  *) printf 'usage: %s [--next|--toggle|EN|TH]\n' "$0" >&2; exit 1 ;;
esac

current=""
if [[ -x "$DETECT" ]]; then
  current="$("$DETECT" 2>/dev/null || true)"
  [[ "$current" == "UNKNOWN" ]] && current=""
fi
if [[ "$WANT" == "NEXT" ]]; then
  if [[ "$current" == "TH" ]]; then WANT="EN"; else WANT="TH"; fi
fi

switch_to() {
  local want="$1"
  local lwant
  lwant="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')"
  # macOS (Darwin): switch via $IM_SELECTOR (macism preferred, im-select fallback)
  if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
    local sel="${IM_SELECTOR:-}"
    case "${sel##*/}" in
      "" ) : ;;
      macism|im-select) sel="${sel##*/}" ;;
      *) sel="" ;;
    esac
    if [[ -z "$sel" ]]; then
      if command -v macism >/dev/null 2>&1; then sel="macism";
      elif command -v im-select >/dev/null 2>&1; then sel="im-select"; fi
    fi
    if [[ -n "$sel" ]] && command -v "$sel" >/dev/null 2>&1; then
      if [[ "$want" == "TH" ]]; then
        "$sel" com.apple.keylayout.Thai >/dev/null 2>&1 && return 0
        "$sel" Thai >/dev/null 2>&1 && return 0
      else
        "$sel" com.apple.keylayout.ABC >/dev/null 2>&1 && return 0
        "$sel" com.apple.keylayout.US >/dev/null 2>&1 && return 0
        "$sel" ABC >/dev/null 2>&1 && return 0
        "$sel" US >/dev/null 2>&1 && return 0
      fi
    fi
    return 1
  fi
  # hyprctl switchxkblayout (all keyboards, next-aware)
  if command -v hyprctl >/dev/null 2>&1; then
    dev="$(hyprctl devices -j 2>/dev/null | grep -Eo '"name": *"[^"]+"' | head -n1 | cut -d'"' -f4 || true)"
    if [[ -n "${dev:-}" ]]; then
      hyprctl switchxkblayout "$dev" "$lwant" >/dev/null 2>&1 && return 0
      hyprctl switchxkblayout "$dev" next >/dev/null 2>&1 && return 0
    else
      hyprctl switchxkblayout next >/dev/null 2>&1 && return 0
    fi
  fi
  # fcitx5-remote: -s switches (im name varies); best effort
  if command -v fcitx5-remote >/dev/null 2>&1; then
    if [[ "$want" == "TH" ]]; then
      fcitx5-remote -s thai 2>/dev/null && return 0
      fcitx5-remote -s keyboard-th 2>/dev/null && return 0
    else
      fcitx5-remote -s keyboard-us 2>/dev/null && return 0
    fi
    fcitx5-remote -t 2>/dev/null && return 0
  fi
  # ibus engine switch
  if command -v ibus >/dev/null 2>&1; then
    if [[ "$want" == "TH" ]]; then
      ibus engine 'xkb:th::tha' 2>/dev/null && return 0
    else
      ibus engine 'xkb:us::eng' 2>/dev/null && return 0
    fi
  fi
  # gsettings: move wanted source to front of mru-sources
  if command -v gsettings >/dev/null 2>&1; then
    mru="$(gsettings get org.gnome.desktop.input-sources mru-sources 2>/dev/null || true)"
    if [[ -n "$mru" ]]; then
      entry="$(printf '%s' "$mru" | grep -Eo "\('[^']+', *'[^']*'\)" | grep -i "$lwant" | head -n1 || true)"
      if [[ -n "$entry" ]]; then
        rest="$(printf '%s' "$mru" | grep -Eo "\('[^']+', *'[^']*'\)" | grep -vi "$lwant" || true)"
        new="[${entry}$(printf '%s' "$rest" | sed 's/^/, /' | tr '\n' ' ' | sed 's/ *$//')]"
        gsettings set org.gnome.desktop.input-sources mru-sources "$new" >/dev/null 2>&1 && return 0
      fi
    fi
  fi
  # setxkbmap last resort
  if command -v setxkbmap >/dev/null 2>&1; then
    if [[ "$want" == "TH" ]]; then
      setxkbmap -layout th 2>/dev/null && return 0
    else
      setxkbmap -layout us 2>/dev/null && return 0
    fi
  fi
  return 1
}

switch_to "$WANT" || true

# Verify-before-cache (both branches): re-detect after settle, only cache on match
sleep 0.2 2>/dev/null || true
code=""
if [[ -x "$DETECT" ]]; then
  code="$("$DETECT" 2>/dev/null || true)"
fi
if [[ "$code" == "$WANT" && "$code" =~ ^[A-Za-z]{2}$ && "$code" != "UNKNOWN" ]]; then
  tmp="$(mktemp "${CACHE}.tmp.XXXXXX" 2>/dev/null)" && { printf '%s' "$code" > "$tmp" 2>/dev/null && mv -f "$tmp" "$CACHE" 2>/dev/null || rm -f "$tmp"; }
elif [[ "$code" =~ ^[A-Za-z]{2}$ && "$code" != "UNKNOWN" ]]; then
  : # mismatch: leave cache untouched (verify failed)
else
  code="$(cat "$CACHE" 2>/dev/null || printf '%s' "$WANT")"
  [[ "$code" =~ ^[A-Za-z]{2}$ ]] || code="$WANT"
fi

# Best-effort push to wezterm via user var
if command -v wezterm >/dev/null 2>&1 && command -v base64 >/dev/null 2>&1; then
  b64="$(printf '%s' "$code" | base64 2>/dev/null | tr -d '\n' || true)"
  if [[ -n "${b64:-}" ]]; then
    wezterm cli set-user-var KB "$code" >/dev/null 2>&1 || true
    printf '\033]1337;SetUserVar=KB=%s\007' "$b64" > /dev/tty 2>/dev/null || true
  fi
fi
printf '%s\n' "$code"
