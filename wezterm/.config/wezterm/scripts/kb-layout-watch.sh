#!/usr/bin/env bash
# Push daemon: blocking gsettings monitor -> detector -> atomic cache. No polling.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect-layout.sh"
_KB_DIR="${XDG_RUNTIME_DIR:-/tmp}"
if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "${HOME}/.cache" ]]; then _KB_DIR="${HOME}/.cache"; fi
command mkdir -p "$_KB_DIR" 2>/dev/null || { _KB_DIR="/tmp"; command mkdir -p "$_KB_DIR" 2>/dev/null || true; }
CACHE="${_KB_DIR}/wezterm-kb-layout"

# Singleton guard: one daemon per user (zshrc + gui-startup both spawn).
LOCKFILE="${_KB_DIR}/wezterm-kb-layout-watch.${USER:-$(id -un 2>/dev/null)}.lock"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCKFILE" 2>/dev/null || true
  flock -n 9 2>/dev/null || exit 0
else
  if pgrep -f "kb-layout-watch\.sh" >/dev/null 2>&1; then
    _self="$(printf '%s' "$$")"
    _others="$(pgrep -f "kb-layout-watch\.sh" 2>/dev/null | grep -vx "$_self" || true)"
    [[ -n "$_others" ]] && exit 0
  fi
fi

publish() {
  local code cached=""
  code="$("$DETECT" 2>/dev/null || true)"
  [[ "$code" =~ ^[A-Za-z]{2}$ && "$code" != "UNKNOWN" ]] || return 0
  [[ -f "$CACHE" ]] && cached="$(cat "$CACHE" 2>/dev/null)" || cached=""
  [[ "$cached" == "$code" ]] && return 0
  local tmp
  tmp="$(mktemp "${CACHE}.tmp.XXXXXX" 2>/dev/null)" || return 0
  printf '%s' "$code" > "$tmp" 2>/dev/null || return 0
  mv -f "$tmp" "$CACHE" 2>/dev/null || rm -f "$tmp"
}

publish_fast() {
  local code cached=""
  code="$(FAST=1 "$DETECT" 2>/dev/null || true)"
  [[ "$code" =~ ^[A-Za-z]{2}$ && "$code" != "UNKNOWN" ]] || return 0
  [[ -f "$CACHE" ]] && cached="$(cat "$CACHE" 2>/dev/null)" || cached=""
  [[ "$cached" == "$code" ]] && return 0
  local tmp
  tmp="$(mktemp "${CACHE}.tmp.XXXXXX" 2>/dev/null)" || return 0
  printf '%s' "$code" > "$tmp" 2>/dev/null || return 0
  mv -f "$tmp" "$CACHE" 2>/dev/null || rm -f "$tmp"
}

publish

# macOS (Darwin): no gsettings monitor; poll at 2s (external-heal budget).
# Darwin publish_fast uses FAST=1 (cache + macism/im-select only, never
# `defaults`); equality short-circuit skips mktemp/mv when unchanged.
# Darwin-only; tune KB_DARWIN_POLL (1.5-2s).
if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
  _poll="${KB_DARWIN_POLL:-2}"
  while true; do
    sleep "$_poll"
    publish_fast
  done
  exit 0
fi

command -v gsettings >/dev/null 2>&1 || exit 0
gsettings monitor org.gnome.desktop.input-sources mru-sources 2>/dev/null | while IFS= read -r _; do
  publish
done
