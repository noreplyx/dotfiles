#!/usr/bin/env bash
# On-demand screen & system idle sleep inhibitor for Herdr (prefix+shift+a).
# Usage: keep-awake.sh [--toggle|--on|--off|--status|--badge]
set -uo pipefail

detect_platform() {
  local kernel_name
  kernel_name="$(uname -s 2>/dev/null || true)"
  case "${OS:-} ${OSTYPE:-} ${kernel_name}" in
    *[Ww]indows*|*MINGW*|*MSYS*|*CYGWIN*)
      printf 'windows'
      return 0
      ;;
  esac
  if [[ "$kernel_name" == "Darwin" ]]; then
    printf 'macos'
    return 0
  fi
  if [[ -n "${WSL_DISTRO_NAME:-}" || -e /proc/sys/fs/binfmt_misc/WSLInterop ]] || \
     { [[ -r /proc/version ]] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; }; then
    printf 'wsl'
    return 0
  fi
  printf 'linux'
}

resolve_powershell() {
  if command -v powershell.exe >/dev/null 2>&1; then
    printf 'powershell.exe'
    return 0
  fi
  if command -v pwsh.exe >/dev/null 2>&1; then
    printf 'pwsh.exe'
    return 0
  fi
  if command -v pwsh >/dev/null 2>&1; then
    printf 'pwsh'
    return 0
  fi
  return 1
}

PLATFORM="$(detect_platform)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS1_SCRIPT="${SCRIPT_DIR}/keep-awake.ps1"
windows_powershell_script_path="$PS1_SCRIPT"
if [[ "$PLATFORM" == "windows" ]] && command -v cygpath >/dev/null 2>&1; then
  windows_powershell_script_path="$(cygpath -w "$PS1_SCRIPT" 2>/dev/null || printf '%s' "$PS1_SCRIPT")"
elif [[ "$PLATFORM" == "wsl" ]] && command -v wslpath >/dev/null 2>&1; then
  windows_powershell_script_path="$(wslpath -w "$PS1_SCRIPT" 2>/dev/null || printf '%s' "$PS1_SCRIPT")"
fi
powershell_binary="$(resolve_powershell || true)"

if [[ "$PLATFORM" == "windows" ]]; then
  if [[ -z "$powershell_binary" ]]; then
    printf 'keep-awake: powershell not found for platform %s\n' "$PLATFORM" >&2
    printf 'OFF\n'
    exit 1
  fi
  exec "$powershell_binary" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$windows_powershell_script_path" "${1:---toggle}"
fi

RUNTIME_STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "${HOME:-}/.cache" ]]; then
  RUNTIME_STATE_DIR="${HOME}/.cache"
fi
command mkdir -p "$RUNTIME_STATE_DIR" 2>/dev/null || {
  RUNTIME_STATE_DIR="/tmp"
  command mkdir -p "$RUNTIME_STATE_DIR" 2>/dev/null || true
}

STATE_FILE="${RUNTIME_STATE_DIR}/herdr-keep-awake"
WATCHDOG_PID_FILE="${RUNTIME_STATE_DIR}/herdr-keep-awake.pid"
INHIBITOR_PID_FILE="${RUNTIME_STATE_DIR}/herdr-keep-awake.child.pid"

write_state() {
  local state="$1" temp_state_file mirror_destination_path
  temp_state_file="$(command mktemp "${STATE_FILE}.tmp.XXXXXX" 2>/dev/null)" || temp_state_file=""
  if [[ -n "$temp_state_file" ]]; then
    if printf '%s\n' "$state" > "$temp_state_file" 2>/dev/null; then
      mv -f "$temp_state_file" "$STATE_FILE" 2>/dev/null || rm -f "$temp_state_file" 2>/dev/null || true
    else
      rm -f "$temp_state_file" 2>/dev/null || true
    fi
  else
    printf '%s\n' "$state" > "$STATE_FILE" 2>/dev/null || true
  fi
  local mirror_targets=("${HOME:-}/.cache/herdr-keep-awake" "/tmp/herdr-keep-awake")
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR}" ]]; then
    mirror_targets+=("${XDG_RUNTIME_DIR}/herdr-keep-awake")
  fi
  for mirror_destination_path in "${mirror_targets[@]}"; do
    [[ "$mirror_destination_path" == "$STATE_FILE" ]] && continue
    printf '%s\n' "$state" > "$mirror_destination_path" 2>/dev/null || true
  done
}

resolve_herdr() {
  if [[ -n "${HERDR_BIN_PATH:-}" && -f "${HERDR_BIN_PATH}" ]]; then
    printf '%s' "$HERDR_BIN_PATH"
    return 0
  fi
  if command -v herdr >/dev/null 2>&1; then
    printf 'herdr'
    return 0
  fi
  if [[ -n "${HOME:-}" && -x "${HOME}/.herdr/packages/standalone/current/herdr" ]]; then
    printf '%s' "${HOME}/.herdr/packages/standalone/current/herdr"
    return 0
  fi
  if [[ -n "${HOME:-}" && -x "${HOME}/.herdr/bin/herdr" ]]; then
    printf '%s' "${HOME}/.herdr/bin/herdr"
    return 0
  fi
  return 1
}

has_inhibitor_backend() {
  case "$PLATFORM" in
    macos)
      command -v caffeinate >/dev/null 2>&1
      ;;
    wsl)
      [[ -n "$powershell_binary" && -f "$PS1_SCRIPT" ]]
      ;;
    linux)
      command -v gnome-session-inhibit >/dev/null 2>&1 || \
        command -v systemd-inhibit >/dev/null 2>&1 || \
        command -v gdbus >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

get_posix_herdr_pid() {
  local pid="" user_name
  if command -v pgrep >/dev/null 2>&1; then
    user_name="${USER:-$(id -un 2>/dev/null || true)}"
    if [[ -n "$user_name" ]]; then
      pid="$(pgrep -u "$user_name" -x herdr 2>/dev/null | head -n1 || true)"
    fi
    if [[ -z "$pid" ]]; then
      pid="$(pgrep -x herdr 2>/dev/null | head -n1 || true)"
    fi
    if [[ -n "$pid" ]]; then
      printf '%s' "$pid"
      return 0
    fi
  fi
  return 1
}

is_pid_alive() {
  local pid="$1"
  [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

is_active() {
  if [[ ! -f "$WATCHDOG_PID_FILE" ]]; then
    return 1
  fi
  local pid=""
  pid="$(sed -n '1p' "$WATCHDOG_PID_FILE" 2>/dev/null | tr -d ' \t\r\n' || true)"
  is_pid_alive "$pid"
}

clear_stale_state() {
  if [[ -f "$WATCHDOG_PID_FILE" ]] && ! is_active; then
    rm -f "$WATCHDOG_PID_FILE" "$INHIBITOR_PID_FILE" 2>/dev/null || true
    write_state "OFF"
  fi
}

notify_user() {
  local state="$1"
  local herdr_binary_path
  herdr_binary_path="$(resolve_herdr || true)"
  if [[ -n "$herdr_binary_path" ]]; then
    "$herdr_binary_path" notification show "Keep-Awake: ${state}" \
      --body "Screen & system idle sleep inhibition is ${state}" \
      --position top-right --sound none >/dev/null 2>&1 || true
  fi
}

stop_inhibitor() {
  local watchdog_pid="" child_pid=""
  if [[ -f "$WATCHDOG_PID_FILE" ]]; then
    watchdog_pid="$(sed -n '1p' "$WATCHDOG_PID_FILE" 2>/dev/null | tr -d ' \t\r\n' || true)"
  fi
  if [[ -f "$INHIBITOR_PID_FILE" ]]; then
    child_pid="$(sed -n '1p' "$INHIBITOR_PID_FILE" 2>/dev/null | tr -d ' \t\r\n' || true)"
  fi

  rm -f "$WATCHDOG_PID_FILE" "$INHIBITOR_PID_FILE" 2>/dev/null || true

  if is_pid_alive "$child_pid"; then
    kill -TERM "$child_pid" 2>/dev/null || true
  fi
  if is_pid_alive "$watchdog_pid"; then
    if command -v pkill >/dev/null 2>&1; then
      pkill -TERM -P "$watchdog_pid" 2>/dev/null || true
    fi
    kill -TERM "$watchdog_pid" 2>/dev/null || true
  fi
  write_state "OFF"
}

run_watchdog() {
  local started_with_herdr="$1"
  local herdr_pid="${2:-}"
  local inhibitor_pid=""
  local dbus_cookie=""
  local watchdog_self_pid="${BASHPID:-$$}"

  printf '%s\n' "$watchdog_self_pid" > "$WATCHDOG_PID_FILE" 2>/dev/null || true

  cleanup_watchdog() {
    trap - EXIT INT TERM HUP
    if [[ -n "$dbus_cookie" ]] && command -v gdbus >/dev/null 2>&1; then
      gdbus call --session \
        --dest org.freedesktop.ScreenSaver \
        --object-path /org/freedesktop/ScreenSaver \
        --method org.freedesktop.ScreenSaver.UnInhibit \
        "$dbus_cookie" >/dev/null 2>&1 || true
    fi
    if [[ -f "$INHIBITOR_PID_FILE" ]]; then
      local recorded_child
      recorded_child="$(sed -n '1p' "$INHIBITOR_PID_FILE" 2>/dev/null | tr -d ' \t\r\n' || true)"
      if is_pid_alive "$recorded_child"; then
        kill -TERM "$recorded_child" 2>/dev/null || true
      fi
    fi
    if is_pid_alive "$inhibitor_pid"; then
      kill -TERM "$inhibitor_pid" 2>/dev/null || true
    fi
    rm -f "$WATCHDOG_PID_FILE" "$INHIBITOR_PID_FILE" 2>/dev/null || true
    write_state "OFF"
    exit 0
  }

  trap cleanup_watchdog EXIT INT TERM HUP

  case "$PLATFORM" in
    macos)
      if command -v caffeinate >/dev/null 2>&1; then
        caffeinate -d -i </dev/null >/dev/null 2>&1 &
        inhibitor_pid=$!
      fi
      ;;
    wsl)
      if [[ -n "$powershell_binary" && -f "$PS1_SCRIPT" ]]; then
        local windows_sentinel_path="$WATCHDOG_PID_FILE"
        if command -v wslpath >/dev/null 2>&1; then
          windows_sentinel_path="$(wslpath -w "$WATCHDOG_PID_FILE" 2>/dev/null || printf '%s' "$WATCHDOG_PID_FILE")"
        fi
        "$powershell_binary" -WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$windows_powershell_script_path" --hold-sentinel "$windows_sentinel_path" </dev/null >/dev/null 2>&1 &
        inhibitor_pid=$!
      fi
      ;;
    linux)
      if command -v gnome-session-inhibit >/dev/null 2>&1; then
        gnome-session-inhibit --inhibit idle:suspend --reason "Herdr keep-awake" --app-id "herdr" sleep infinity </dev/null >/dev/null 2>&1 &
        inhibitor_pid=$!
      elif command -v systemd-inhibit >/dev/null 2>&1; then
        systemd-inhibit --what=idle:sleep --who="Herdr" --why="Keep-awake active" --mode=block sleep infinity </dev/null >/dev/null 2>&1 &
        inhibitor_pid=$!
      elif command -v gdbus >/dev/null 2>&1; then
        local reply
        reply="$(gdbus call --session \
          --dest org.freedesktop.ScreenSaver \
          --object-path /org/freedesktop/ScreenSaver \
          --method org.freedesktop.ScreenSaver.Inhibit \
          "herdr" "Herdr keep-awake" 2>/dev/null || true)"
        dbus_cookie="$(printf '%s' "$reply" | grep -Eo '[0-9]+' | head -n1 || true)"
      fi
      ;;
  esac

  if [[ -z "$inhibitor_pid" && -z "$dbus_cookie" ]]; then
    cleanup_watchdog
  fi

  if [[ -n "$inhibitor_pid" ]]; then
    printf '%s\n' "$inhibitor_pid" > "$INHIBITOR_PID_FILE" 2>/dev/null || true
  fi

  while [[ -f "$WATCHDOG_PID_FILE" ]]; do
    if [[ -n "$inhibitor_pid" ]] && ! is_pid_alive "$inhibitor_pid"; then
      break
    fi
    if [[ "$started_with_herdr" == "1" ]]; then
      if [[ "$herdr_pid" =~ ^[0-9]+$ ]]; then
        if ! is_pid_alive "$herdr_pid"; then
          herdr_pid="$(get_posix_herdr_pid || true)"
          [[ -z "$herdr_pid" ]] && break
        fi
      else
        herdr_pid="$(get_posix_herdr_pid || true)"
        [[ -z "$herdr_pid" ]] && break
      fi
    fi
    sleep 5 2>/dev/null || break
  done

  cleanup_watchdog
}

enable_keep_awake() {
  clear_stale_state
  if is_active; then
    write_state "ON"
    notify_user "ON"
    printf 'ON\n'
    return 0
  fi

  if ! has_inhibitor_backend; then
    write_state "OFF"
    printf 'keep-awake: no supported inhibitor backend found for platform %s\n' "$PLATFORM" >&2
    printf 'OFF\n'
    return 1
  fi

  local started_with_herdr=0
  local initial_herdr_pid=""
  initial_herdr_pid="$(get_posix_herdr_pid || true)"
  if [[ -n "$initial_herdr_pid" ]]; then
    started_with_herdr=1
  fi

  write_state "ON"
  notify_user "ON"

  (
    run_watchdog "$started_with_herdr" "$initial_herdr_pid"
  ) </dev/null >/dev/null 2>&1 &
  local watchdog_pid=$!
  printf '%s\n' "$watchdog_pid" > "$WATCHDOG_PID_FILE" 2>/dev/null || true
  disown "$watchdog_pid" 2>/dev/null || true

  printf 'ON\n'
}

disable_keep_awake() {
  write_state "OFF"
  notify_user "OFF"
  stop_inhibitor
  printf 'OFF\n'
}

print_keep_awake_status() {
  clear_stale_state
  if is_active; then
    write_state "ON"
    printf 'ON\n'
  else
    write_state "OFF"
    printf 'OFF\n'
  fi
}

print_keep_awake_badge() {
  clear_stale_state
  local cached_state=""
  if [[ -f "$STATE_FILE" ]]; then
    cached_state="$(sed -n '1p' "$STATE_FILE" 2>/dev/null | tr -d ' \t\r\n' | tr '[:lower:]' '[:upper:]' || true)"
  fi
  if [[ "$cached_state" == "ON" ]] || is_active; then
    printf 'AWAKE: ON\n'
  else
    printf 'AWAKE: OFF\n'
  fi
}

action="${1:---toggle}"
case "$action" in
  --toggle)
    clear_stale_state
    if is_active; then
      disable_keep_awake
    else
      enable_keep_awake
    fi
    ;;
  --on)
    enable_keep_awake
    ;;
  --off)
    disable_keep_awake
    ;;
  --status)
    print_keep_awake_status
    ;;
  --badge)
    print_keep_awake_badge
    ;;
  *)
    printf 'usage: keep-awake.sh [--toggle|--on|--off|--status|--badge]\n' >&2
    exit 1
    ;;
esac
