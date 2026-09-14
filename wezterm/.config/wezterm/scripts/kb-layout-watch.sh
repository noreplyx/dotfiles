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
LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/wezterm-kb-layout-watch.${USER:-$(id -un 2>/dev/null)}.lock"
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

publish

# macOS (Darwin): no gsettings monitor; poll backed off to 5s. Cost note:
# each publish() forks detector (~10 forks worst case), so 1.5s polling
# costs ~40 forks/min forever; 5s + cache-equality short-circuit (publish
# returns before mktemp/mv when unchanged) cuts it to ~12/min idle.
# Darwin-only file events unavailable; keep polling, tune KB_DARWIN_POLL.
if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
  _poll="${KB_DARWIN_POLL:-5}"
  while true; do
    sleep "$_poll"
    publish
  done
  exit 0
fi

command -v gsettings >/dev/null 2>&1 || exit 0
gsettings monitor org.gnome.desktop.input-sources mru-sources 2>/dev/null | while IFS= read -r _; do
  publish
done
