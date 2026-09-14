#!/usr/bin/env bash
# Toggle/switch keyboard layout. Usage: toggle-layout.sh [--next|--toggle|EN|TH]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect-layout.sh"
_KB_DIR="${XDG_RUNTIME_DIR:-/tmp}"
if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "${HOME}/.cache" ]]; then _KB_DIR="${HOME}/.cache"; fi
command mkdir -p "$_KB_DIR" 2>/dev/null || { _KB_DIR="/tmp"; command mkdir -p "$_KB_DIR" 2>/dev/null || true; }
CACHE="${_KB_DIR}/wezterm-kb-layout"
_OS="$(uname -s 2>/dev/null || true)"

target="${1:---toggle}"
case "$target" in
  --next|--toggle|toggle|next) WANT="NEXT" ;;
  EN|en|En) WANT="EN" ;;
  TH|th|Th) WANT="TH" ;;
  *) printf 'usage: %s [--next|--toggle|EN|TH]\n' "$0" >&2; exit 1 ;;
esac

current=""
if [[ "$WANT" == "NEXT" ]]; then
  if [[ -r "$CACHE" ]]; then
    current="$(cat "$CACHE" 2>/dev/null | tr -d ' \t\r\n' || true)"
    case "$current" in EN|en|En) current="EN" ;; TH|th|Th) current="TH" ;; *) current="" ;; esac
  fi
  if [[ -z "$current" && -x "$DETECT" ]]; then
    current="$(FAST=1 "$DETECT" 2>/dev/null || true)"
    [[ "$current" == "UNKNOWN" ]] && current=""
  fi
  if [[ "$current" == "TH" ]]; then WANT="EN"; else WANT="TH"; fi
fi

push_want() {
  local code="$1" tmp b64
  tmp="$(mktemp "${CACHE}.tmp.XXXXXX" 2>/dev/null)" && { printf '%s' "$code" > "$tmp" 2>/dev/null && mv -f "$tmp" "$CACHE" 2>/dev/null || rm -f "$tmp"; }
  # Darwin: skip `wezterm cli` (extra fork + socket round-trip); OSC+cache is enough.
  if [[ "$_OS" != "Darwin" ]]; then
    if command -v wezterm >/dev/null 2>&1; then
      wezterm cli set-user-var KB "$code" >/dev/null 2>&1 || true
    fi
  fi
  if command -v base64 >/dev/null 2>&1; then
    b64="$(printf '%s' "$code" | base64 2>/dev/null | tr -d '\n' || true)"
    [[ -n "${b64:-}" ]] && { printf '\033]1337;SetUserVar=KB=%s\007' "$b64" > /dev/tty; } 2>/dev/null || true;
  fi
}

switch_to() {
  local want="$1"
  local lwant
  lwant="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')"
  _verify_want() {
    local want="$1" got=""
    if [[ -x "$DETECT" ]]; then
      got="$("$DETECT" 2>/dev/null || true)"
      got="$(printf '%s' "$got" | tr '[:lower:]' '[:upper:]' | tr -d ' \t\r\n' || true)"
      case "$got" in EN) got="EN" ;; TH) got="TH" ;; *) got="" ;; esac
    fi
    [[ -n "$got" && "$got" == "$want" ]]
  }
  # Optimistic success: backend command winning means return 0; push cache
  # first so display never '--', background heal corrects any mismatch.
  _ok() {
    local want="$1"
    push_want "$want"
    _verify_want "$want" || true
    return 0
  }
  # macOS (Darwin): switch via cached $IM_SELECTOR (macism preferred, im-select
  # fallback) and cached input IDs: single fork per switch after first resolve.
  if [[ "$_OS" == "Darwin" ]]; then
    local sel="${IM_SELECTOR:-}" sel_cache="${_KB_DIR}/wezterm-kb-selector"
    local id_cache="${_KB_DIR}/wezterm-kb-ids"
    local sel_from_cache="" warm=0
    if [[ -z "$sel" && -r "$sel_cache" ]]; then
      sel="$(cat "$sel_cache" 2>/dev/null | tr -d ' \t\r\n' || true)"
      [[ -n "$sel" ]] && sel_from_cache=1
    fi
    case "${sel##*/}" in
      "" ) : ;;
      macism|im-select) sel="${sel##*/}" ;;
      *) sel=""; sel_from_cache="" ;;
    esac
    local id_en="" id_th=""
    if [[ -r "$id_cache" ]]; then
      id_en="$(sed -n '1p' "$id_cache" 2>/dev/null | tr -d '\r\n' || true)"
      id_th="$(sed -n '2p' "$id_cache" 2>/dev/null | tr -d '\r\n' || true)"
    fi
    if [[ -n "$sel_from_cache" && -n "$id_en" && -n "$id_th" ]]; then warm=1; fi
    if [[ "$warm" == "1" ]]; then
      if [[ "$want" == "TH" ]]; then
        "$sel" "$id_th" >/dev/null 2>&1 && _verify_want "$want" && return 0
      else
        "$sel" "$id_en" >/dev/null 2>&1 && _verify_want "$want" && return 0
      fi
      rm -f "$id_cache" 2>/dev/null || true
      id_en=""; id_th=""
      sel=""; sel_from_cache=""
    fi
    if [[ -z "$sel" ]]; then
      if command -v macism >/dev/null 2>&1; then sel="macism";
      elif command -v im-select >/dev/null 2>&1; then sel="im-select"; fi
      [[ -n "$sel" ]] && printf '%s' "$sel" > "$sel_cache" 2>/dev/null || true
    elif [[ -z "$sel_from_cache" ]] && ! command -v "$sel" >/dev/null 2>&1; then
      sel=""
      if command -v macism >/dev/null 2>&1; then sel="macism";
      elif command -v im-select >/dev/null 2>&1; then sel="im-select"; fi
      [[ -n "$sel" ]] && printf '%s' "$sel" > "$sel_cache" 2>/dev/null || true
    fi
    if [[ -n "$sel" ]]; then
      _darwin_ids_for() {
        local w="$1" out=""
        if [[ "$sel" == "macism" ]]; then
          out="$(macism list 2>/dev/null || true)"
        fi
        if [[ -z "$out" ]]; then
          out="$(defaults read com.apple.HIToolbox AppleInputSourceHistory 2>/dev/null || true)"
          [[ -z "$out" ]] && out="$(defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null || true)"
        fi
        if [[ "$w" == "TH" ]]; then
          printf '%s\n' "$out" | grep -Eo 'com\.apple\.keylayout\.[A-Za-z0-9_-]+|[A-Za-z]*Thai[A-Za-z]*' 2>/dev/null | head -n5 || true
          printf 'com.apple.keylayout.Thai\nThai\ncom.apple.keylayout.ThaiKedmanee\n'
        else
          printf '%s\n' "$out" | grep -Eo 'com\.apple\.keylayout\.[A-Za-z0-9_-]+|ABC|US' 2>/dev/null | grep -Ei 'abc|^us$|\.us' | head -n5 || true
          printf 'com.apple.keylayout.ABC\ncom.apple.keylayout.US\ncom.apple.keylayout.USInternational\nABC\nUS\n'
        fi
      }
      if [[ -z "$id_en" || -z "$id_th" ]]; then
        if [[ "$want" == "TH" ]]; then
          while IFS= read -r _id; do
            [[ -z "$_id" ]] && continue
            "$sel" "$_id" >/dev/null 2>&1 && _verify_want "$want" && { id_th="$_id"; break; }
          done < <(_darwin_ids_for TH)
          id_en="${id_en:-com.apple.keylayout.ABC}"
        else
          while IFS= read -r _id; do
            [[ -z "$_id" ]] && continue
            "$sel" "$_id" >/dev/null 2>&1 && _verify_want "$want" && { id_en="$_id"; break; }
          done < <(_darwin_ids_for EN)
          id_th="${id_th:-com.apple.keylayout.Thai}"
        fi
        # Cache only the verified working ID; drop cache when verify failed.
        if _verify_want "$want"; then
          { printf '%s\n%s\n' "$id_en" "$id_th" > "$id_cache"; } 2>/dev/null || true
          push_want "$want"
          return 0
        fi
        rm -f "$id_cache" 2>/dev/null || true
        return 1
      fi
      if [[ "$want" == "TH" ]]; then
        "$sel" "$id_th" >/dev/null 2>&1 && _verify_want "$want" && return 0
      else
        "$sel" "$id_en" >/dev/null 2>&1 && _verify_want "$want" && return 0
      fi
      rm -f "$id_cache" 2>/dev/null || true
    fi
    return 1
  fi
  # hyprctl switchxkblayout (all keyboards, next-aware)
  if command -v hyprctl >/dev/null 2>&1; then
    dev="$(hyprctl devices -j 2>/dev/null | grep -Eo '"name": *"[^"]+"' | head -n1 | cut -d'"' -f4 || true)"
    if [[ -n "${dev:-}" ]]; then
      hyprctl switchxkblayout "$dev" "$lwant" >/dev/null 2>&1 && { _ok "$want"; return 0; }
      hyprctl switchxkblayout "$dev" next >/dev/null 2>&1 && { _ok "$want"; return 0; }
    else
      hyprctl switchxkblayout next >/dev/null 2>&1 && { _ok "$want"; return 0; }
    fi
  fi
  # fcitx5-remote: -s switches (im name varies); best effort
  if command -v fcitx5-remote >/dev/null 2>&1; then
    if [[ "$want" == "TH" ]]; then
      fcitx5-remote -s thai 2>/dev/null && { _ok "$want"; return 0; }
      fcitx5-remote -s keyboard-th 2>/dev/null && { _ok "$want"; return 0; }
    else
      fcitx5-remote -s keyboard-us 2>/dev/null && { _ok "$want"; return 0; }
    fi
    fcitx5-remote -t 2>/dev/null && { _ok "$want"; return 0; }
  fi
  # ibus engine switch
  if command -v ibus >/dev/null 2>&1; then
    if [[ "$want" == "TH" ]]; then
      ibus engine 'xkb:th::tha' 2>/dev/null && { _ok "$want"; return 0; }
    else
      ibus engine 'xkb:us::eng' 2>/dev/null && { _ok "$want"; return 0; }
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
        gsettings set org.gnome.desktop.input-sources mru-sources "$new" >/dev/null 2>&1 && { _ok "$want"; return 0; }
      fi
    fi
  fi
  # setxkbmap last resort
  if command -v setxkbmap >/dev/null 2>&1; then
    if [[ "$want" == "TH" ]]; then
      setxkbmap -layout th 2>/dev/null && { _ok "$want"; return 0; }
    else
      setxkbmap -layout us 2>/dev/null && { _ok "$want"; return 0; }
    fi
  fi
  return 1
}

# Optimistic push: cache + dual user-var push + stdout immediately (no fork
# beyond cache write/wezterm cli), then heal in background.
push_want "$WANT"
printf '%s\n' "$WANT"

# Background heal: real switch, settle 0.5-0.8s, full detect, correct cache on
# mismatch (transient mismatch never sticks; failure heals in ~2s).
(
  switch_to "$WANT"; sw_rc=$?
  [[ "$sw_rc" != "0" ]] && rm -f "${_KB_DIR}/wezterm-kb-ids" 2>/dev/null || true
  sleep 0.6 2>/dev/null || true
  code=""
  if [[ -x "$DETECT" ]]; then
    code="$("$DETECT" 2>/dev/null || true)"
    code="$(printf '%s' "$code" | tr -d ' \t\r\n' || true)"
  fi
  if [[ "$code" == "UNKNOWN" || -z "$code" ]]; then
    sleep 0.5 2>/dev/null || true
    if [[ -x "$DETECT" ]]; then
      code="$("$DETECT" 2>/dev/null || true)"
      code="$(printf '%s' "$code" | tr -d ' \t\r\n' || true)"
    fi
  fi
  case "$code" in EN|TH) [[ "$code" != "$WANT" ]] && push_want "$code" ;; *) [[ "$sw_rc" != "0" ]] && rm -f "$CACHE" 2>/dev/null || true ;; esac
) >/dev/null 2>&1 & disown 2>/dev/null || true
