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

read_first_line_trimmed() {
  local file_path="$1" line=""
  [[ -f "$file_path" ]] || return 0
  IFS=$' \t\r\n' read -r line < "$file_path" 2>/dev/null || true
  printf '%s' "$line"
}

render_badge_from_files() {
  local badge_file_path="$1"
  local state_file_path="$2"
  local cached_badge=""
  if [[ -f "$badge_file_path" ]]; then
    cached_badge="$(read_first_line_trimmed "$badge_file_path")"
    if [[ -n "$cached_badge" ]]; then
      printf '%s\n' "$cached_badge"
      return 0
    fi
  fi

  local cached_state=""
  if [[ -f "$state_file_path" ]]; then
    cached_state="$(read_first_line_trimmed "$state_file_path")"
  fi
  if [[ "$cached_state" == [Oo][Nn] ]]; then
    printf 'AWAKE: ON\n'
    return 0
  fi

  printf 'AWAKE: OFF\n'
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
  if [[ "${1:-}" == "--badge" || "${1:-}" == "badge" ]]; then
    target_badge="${HOME:-}/.cache/herdr-keep-awake.badge"
    if [[ ! -f "$target_badge" && -n "${USERPROFILE:-}" ]]; then
      target_badge="${USERPROFILE}/.cache/herdr-keep-awake.badge"
    fi
    target_state="${HOME:-}/.cache/herdr-keep-awake"
    if [[ ! -f "$target_state" && -n "${USERPROFILE:-}" ]]; then
      target_state="${USERPROFILE}/.cache/herdr-keep-awake"
    fi
    render_badge_from_files "$target_badge" "$target_state"
    exit 0
  fi

  if [[ -z "$powershell_binary" ]]; then
    printf 'keep-awake: powershell not found for platform %s\n' "$PLATFORM" >&2
    printf 'OFF\n'
    exit 1
  fi
  exec "$powershell_binary" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$windows_powershell_script_path" "${1:---toggle}"
fi

RUNTIME_STATE_DIR="${HOME:-/tmp}/.cache"
command mkdir -p "$RUNTIME_STATE_DIR" 2>/dev/null || {
  RUNTIME_STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
  command mkdir -p "$RUNTIME_STATE_DIR" 2>/dev/null || true
}

STATE_FILE="${RUNTIME_STATE_DIR}/herdr-keep-awake"
BADGE_FILE="${RUNTIME_STATE_DIR}/herdr-keep-awake.badge"
WATCHDOG_PID_FILE="${RUNTIME_STATE_DIR}/herdr-keep-awake.pid"
INHIBITOR_PID_FILE="${RUNTIME_STATE_DIR}/herdr-keep-awake.child.pid"
LOG_FILE="${RUNTIME_STATE_DIR}/herdr-keep-awake.log"

write_atomic_file() {
  local target_path="$1"
  local content="$2"
  local temp_file=""
  temp_file="$(command mktemp "${target_path}.tmp.XXXXXX" 2>/dev/null || true)"
  if [[ -n "$temp_file" ]]; then
    if printf '%s\n' "$content" > "$temp_file" 2>/dev/null; then
      mv -f "$temp_file" "$target_path" 2>/dev/null || rm -f "$temp_file" 2>/dev/null || true
    else
      rm -f "$temp_file" 2>/dev/null || true
    fi
  else
    printf '%s\n' "$content" > "$target_path" 2>/dev/null || true
  fi
}

log_keep_awake_event() {
  local level="$1"
  local operation="$2"
  local message="$3"
  local log_size=0
  if [[ -f "$LOG_FILE" ]]; then
    if [[ "$PLATFORM" == "macos" ]]; then
      log_size="$(stat -f %z "$LOG_FILE" 2>/dev/null || printf '0')"
    else
      log_size="$(stat -c %s "$LOG_FILE" 2>/dev/null || printf '0')"
    fi
    if [[ "$log_size" =~ ^[0-9]+$ ]] && (( log_size > 524288 )); then
      mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
    fi
  fi
  printf '[%s] [%s] operation=%s pid=%s %s\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf 'unknown')" \
    "$level" "$operation" "${BASHPID:-$$}" "$message" >> "$LOG_FILE" 2>/dev/null || true
}

write_state() {
  local state="$1" mirror_destination_path badge_text
  local normalized_state="OFF"
  if [[ "$state" == [Oo][Nn] ]]; then
    normalized_state="ON"
  fi
  badge_text="AWAKE: ${normalized_state}"

  write_atomic_file "$STATE_FILE" "$normalized_state"
  write_atomic_file "$BADGE_FILE" "$badge_text"

  local mirror_targets=("${HOME:-/tmp}/.cache/herdr-keep-awake" "/tmp/herdr-keep-awake")
  local mirror_badge_targets=("${HOME:-/tmp}/.cache/herdr-keep-awake.badge" "/tmp/herdr-keep-awake.badge")
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR}" ]]; then
    mirror_targets+=("${XDG_RUNTIME_DIR}/herdr-keep-awake")
    mirror_badge_targets+=("${XDG_RUNTIME_DIR}/herdr-keep-awake.badge")
  fi
  for mirror_destination_path in "${mirror_targets[@]}"; do
    [[ "$mirror_destination_path" == "$STATE_FILE" ]] && continue
    write_atomic_file "$mirror_destination_path" "$normalized_state"
  done
  for mirror_destination_path in "${mirror_badge_targets[@]}"; do
    [[ "$mirror_destination_path" == "$BADGE_FILE" ]] && continue
    write_atomic_file "$mirror_destination_path" "$badge_text"
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
  local matched_herdr_pid="" user_name
  if command -v pgrep >/dev/null 2>&1; then
    user_name="${USER:-$(id -un 2>/dev/null || true)}"
    if [[ -n "$user_name" ]]; then
      matched_herdr_pid="$(pgrep -u "$user_name" -x herdr 2>/dev/null | head -n1 || true)"
    fi
    if [[ -z "$matched_herdr_pid" ]]; then
      matched_herdr_pid="$(pgrep -x herdr 2>/dev/null | head -n1 || true)"
    fi
    if [[ -z "$matched_herdr_pid" && -n "$user_name" ]]; then
      matched_herdr_pid="$(pgrep -u "$user_name" -f '(^|/)herdr(\.exe)?([[:space:]]|$)' 2>/dev/null | head -n1 || true)"
    fi
    if [[ -z "$matched_herdr_pid" ]]; then
      matched_herdr_pid="$(pgrep -f '(^|/)herdr(\.exe)?([[:space:]]|$)' 2>/dev/null | head -n1 || true)"
    fi
    if [[ -n "$matched_herdr_pid" ]]; then
      printf '%s' "$matched_herdr_pid"
      return 0
    fi
  fi
  return 1
}

get_file_age_seconds() {
  local target_file="$1"
  [[ -f "$target_file" ]] || { printf '999999'; return 0; }
  local now_epoch file_mtime_epoch
  now_epoch="$(date +%s 2>/dev/null || printf '0')"
  if [[ "$PLATFORM" == "macos" ]]; then
    file_mtime_epoch="$(stat -f %m "$target_file" 2>/dev/null || printf '0')"
  else
    file_mtime_epoch="$(stat -c %Y "$target_file" 2>/dev/null || printf '0')"
  fi
  if [[ "$now_epoch" =~ ^[0-9]+$ && "$file_mtime_epoch" =~ ^[0-9]+$ ]] && (( now_epoch >= file_mtime_epoch )); then
    printf '%s' "$(( now_epoch - file_mtime_epoch ))"
  else
    printf '0'
  fi
}

is_pid_alive() {
  local pid="${1#win:}"
  [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

is_active() {
  if [[ ! -f "$WATCHDOG_PID_FILE" ]]; then
    return 1
  fi
  local recorded_token=""
  recorded_token="$(read_first_line_trimmed "$WATCHDOG_PID_FILE")"
  if [[ "$recorded_token" == "starting" ]]; then
    local file_age
    file_age="$(get_file_age_seconds "$WATCHDOG_PID_FILE")"
    (( file_age < 10 )) && return 0
    return 1
  fi
  is_pid_alive "$recorded_token"
}

clear_stale_state() {
  if [[ -f "$WATCHDOG_PID_FILE" ]] && ! is_active; then
    local file_age
    file_age="$(get_file_age_seconds "$WATCHDOG_PID_FILE")"
    if (( file_age >= 2 )); then
      rm -f "$WATCHDOG_PID_FILE" "$INHIBITOR_PID_FILE" 2>/dev/null || true
      write_state "OFF"
    fi
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
  local watchdog_pid="" inhibitor_child_pid=""
  if [[ -f "$WATCHDOG_PID_FILE" ]]; then
    watchdog_pid="$(read_first_line_trimmed "$WATCHDOG_PID_FILE")"
    watchdog_pid="${watchdog_pid#win:}"
  fi
  if [[ -f "$INHIBITOR_PID_FILE" ]]; then
    inhibitor_child_pid="$(read_first_line_trimmed "$INHIBITOR_PID_FILE")"
    inhibitor_child_pid="${inhibitor_child_pid#win:}"
  fi

  rm -f "$WATCHDOG_PID_FILE" "$INHIBITOR_PID_FILE" 2>/dev/null || true

  if is_pid_alive "$inhibitor_child_pid"; then
    kill -TERM "$inhibitor_child_pid" 2>/dev/null || true
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

  local initial_state=""
  if [[ -f "$STATE_FILE" ]]; then
    initial_state="$(read_first_line_trimmed "$STATE_FILE")"
  fi
  if [[ "$initial_state" == [Oo][Ff][Ff] || ! -f "$WATCHDOG_PID_FILE" ]]; then
    log_keep_awake_event "INFO" "watchdog_aborted_off" "keep-awake already OFF before watchdog loop"
    exit 0
  fi

  write_atomic_file "$WATCHDOG_PID_FILE" "$watchdog_self_pid"
  log_keep_awake_event "INFO" "watchdog_started" "startedWithHerdr=${started_with_herdr} herdrPid=${herdr_pid}"

  cleanup_watchdog() {
    trap - EXIT INT TERM HUP
    if [[ -n "$dbus_cookie" ]] && command -v gdbus >/dev/null 2>&1; then
      gdbus call --session \
        --dest org.freedesktop.ScreenSaver \
        --object-path /org/freedesktop/ScreenSaver \
        --method org.freedesktop.ScreenSaver.UnInhibit \
        "$dbus_cookie" >/dev/null 2>&1 || true
    fi
    if is_pid_alive "$inhibitor_pid"; then
      kill -TERM "$inhibitor_pid" 2>/dev/null || true
    fi
    local current_owner=""
    if [[ -f "$WATCHDOG_PID_FILE" ]]; then
      current_owner="$(read_first_line_trimmed "$WATCHDOG_PID_FILE")"
    fi
    if [[ "$current_owner" == "$watchdog_self_pid" ]]; then
      if [[ -f "$INHIBITOR_PID_FILE" ]]; then
        local recorded_child
        recorded_child="$(read_first_line_trimmed "$INHIBITOR_PID_FILE")"
        if is_pid_alive "$recorded_child"; then
          kill -TERM "$recorded_child" 2>/dev/null || true
        fi
      fi
      rm -f "$WATCHDOG_PID_FILE" "$INHIBITOR_PID_FILE" 2>/dev/null || true
      write_state "OFF"
    fi
    log_keep_awake_event "INFO" "watchdog_stopped" "owner=${current_owner}"
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
    write_atomic_file "$INHIBITOR_PID_FILE" "$inhibitor_pid"
  fi

  while [[ -f "$WATCHDOG_PID_FILE" ]]; do
    local current_state=""
    if [[ -f "$STATE_FILE" ]]; then
      current_state="$(read_first_line_trimmed "$STATE_FILE")"
    fi
    if [[ "$current_state" == [Oo][Ff][Ff] ]]; then
      break
    fi
    local recorded_owner=""
    recorded_owner="$(read_first_line_trimmed "$WATCHDOG_PID_FILE")"
    if [[ -n "$recorded_owner" && "$recorded_owner" != "starting" && "$recorded_owner" != "$watchdog_self_pid" ]]; then
      break
    fi
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

start_background_watchdog() {
  local started_with_herdr="$1"
  local initial_herdr_pid="${2:-}"
  write_atomic_file "$WATCHDOG_PID_FILE" "starting"
  (
    nohup "${BASH_SOURCE[0]}" --watchdog "$started_with_herdr" "$initial_herdr_pid" </dev/null >/dev/null 2>&1 &
  ) 2>/dev/null || {
    (
      run_watchdog "$started_with_herdr" "$initial_herdr_pid"
    ) </dev/null >/dev/null 2>&1 &
    local fallback_pid=$!
    disown "$fallback_pid" 2>/dev/null || true
  }
}

enable_keep_awake() {
  clear_stale_state
  if is_active; then
    write_state "ON"
    (notify_user "ON") </dev/null >/dev/null 2>&1 &
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
  start_background_watchdog "$started_with_herdr" "$initial_herdr_pid"
  (notify_user "ON") </dev/null >/dev/null 2>&1 &

  printf 'ON\n'
}

disable_keep_awake() {
  stop_inhibitor
  write_state "OFF"
  (notify_user "OFF") </dev/null >/dev/null 2>&1 &
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

# Liveness reconciliation is deferred to --status/--toggle so --badge remains a pure lock-free cache reader.
print_keep_awake_badge() {
  render_badge_from_files "$BADGE_FILE" "$STATE_FILE"
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
  --watchdog)
    run_watchdog "${2:-0}" "${3:-}"
    ;;
  *)
    printf 'usage: keep-awake.sh [--toggle|--on|--off|--status|--badge]\n' >&2
    exit 1
    ;;
esac
