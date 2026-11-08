#!/usr/bin/env bash
# Detect and manage dotnet run, pnpm run dev, and npm run dev processes across Herdr workspaces and panes.
# Usage: dev-servers.sh [--badge|--scan|--daemon|--open|--pane|--stop [workspaceId|--all]|--help]
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
PS1_SCRIPT="${SCRIPT_DIR}/dev-servers.ps1"

if [[ "$PLATFORM" == "windows" ]]; then
  windows_powershell_script_path="$PS1_SCRIPT"
  if command -v cygpath >/dev/null 2>&1; then
    windows_powershell_script_path="$(cygpath -w "$PS1_SCRIPT" 2>/dev/null || printf '%s' "$PS1_SCRIPT")"
  fi
  powershell_binary="$(resolve_powershell || true)"
  if [[ -z "$powershell_binary" ]]; then
    printf 'dev-servers: powershell not found for platform %s\n' "$PLATFORM" >&2
    printf 'DEV: OFF\n'
    exit 1
  fi
  requested_action="${1:---open}"
  if [[ "$requested_action" == "--pane" || "$requested_action" == "pane" ]]; then
    exec "$powershell_binary" -NoProfile -ExecutionPolicy Bypass -File "$windows_powershell_script_path" "$@"
  fi
  exec "$powershell_binary" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$windows_powershell_script_path" "$@"
fi

CACHE_DIR="${HOME:-/tmp}/.cache"
command mkdir -p "$CACHE_DIR" 2>/dev/null || {
  CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
  command mkdir -p "$CACHE_DIR" 2>/dev/null || true
}

SHELLS_CACHE_DIR="${CACHE_DIR}/herdr-shells"
SNAPSHOT_FILE="${CACHE_DIR}/herdr-dev-servers.json"
BADGE_FILE="${CACHE_DIR}/herdr-dev-servers.badge"
DAEMON_PID_FILE="${CACHE_DIR}/herdr-dev-servers.pid"
LOG_FILE="${CACHE_DIR}/herdr-dev-servers.log"

is_pid_alive() {
  local target_pid="$1"
  target_pid="${target_pid#win:}"
  [[ -n "$target_pid" && "$target_pid" =~ ^[0-9]+$ ]] && kill -0 "$target_pid" 2>/dev/null
}

is_daemon_active() {
  [[ -f "$DAEMON_PID_FILE" ]] || return 1
  local recorded_pid
  recorded_pid="$(sed -n '1p' "$DAEMON_PID_FILE" 2>/dev/null | tr -d ' \t\r\n' || true)"
  is_pid_alive "$recorded_pid"
}

is_file_fresh_within_ten_seconds() {
  local target_file="$1"
  [[ -f "$target_file" ]] || return 1
  local now_epoch file_mtime_epoch
  now_epoch="$(date +%s 2>/dev/null || printf '0')"
  if [[ "$PLATFORM" == "macos" ]]; then
    file_mtime_epoch="$(stat -f %m "$target_file" 2>/dev/null || printf '0')"
  else
    file_mtime_epoch="$(stat -c %Y "$target_file" 2>/dev/null || printf '0')"
  fi
  (( now_epoch - file_mtime_epoch < 10 ))
}

get_posix_herdr_pid() {
  local herdr_pid="" current_user
  if command -v pgrep >/dev/null 2>&1; then
    current_user="${USER:-$(id -un 2>/dev/null || true)}"
    if [[ -n "$current_user" ]]; then
      herdr_pid="$(pgrep -u "$current_user" -x herdr 2>/dev/null | head -n1 || true)"
    fi
    if [[ -z "$herdr_pid" ]]; then
      herdr_pid="$(pgrep -x herdr 2>/dev/null | head -n1 || true)"
    fi
    if [[ -n "$herdr_pid" ]]; then
      printf '%s' "$herdr_pid"
      return 0
    fi
  fi
  return 1
}

read_cached_badge_text() {
  local badge_text="DEV: OFF"
  if [[ -f "$BADGE_FILE" ]]; then
    local raw_badge
    raw_badge="$(sed -n '1p' "$BADGE_FILE" 2>/dev/null | tr -d '\r\n' || true)"
    [[ -n "$raw_badge" ]] && badge_text="$raw_badge"
  fi
  printf '%s' "$badge_text"
}

# Fast path for --badge polling (<10ms when daemon is active or badge file is fresh).
if [[ "${1:-}" == "--badge" || "${1:-}" == "badge" ]]; then
  cached_badge="$(read_cached_badge_text)"
  if is_daemon_active || is_file_fresh_within_ten_seconds "$BADGE_FILE"; then
    printf '%s\n' "$cached_badge"
    exit 0
  fi
  if get_posix_herdr_pid >/dev/null 2>&1; then
    nohup "${BASH_SOURCE[0]}" --daemon </dev/null >/dev/null 2>&1 &
  fi
  printf '%s\n' "$cached_badge"
  exit 0
fi

write_atomic_text_file() {
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
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR}" && "$target_path" == "$BADGE_FILE" ]]; then
    printf '%s\n' "$content" > "${XDG_RUNTIME_DIR}/herdr-dev-servers.badge" 2>/dev/null || true
  fi
}

log_dev_server_event() {
  local level="$1"
  local operation="$2"
  local message="$3"
  local timestamp_iso
  timestamp_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf 'unknown-time')"
  printf '[%s] [%s] operation=%s pid=%s %s\n' "$timestamp_iso" "$level" "$operation" "$$" "$message" >> "$LOG_FILE" 2>/dev/null || true
}

resolve_herdr_binary() {
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

resolve_herdr_session_file() {
  local candidate_path
  for candidate_path in \
    "${HOME:-}/.config/herdr/session.json" \
    "${HOME:-}/Library/Application Support/herdr/session.json"; do
    if [[ -f "$candidate_path" ]]; then
      printf '%s' "$candidate_path"
      return 0
    fi
  done
  return 1
}

match_workspace_from_session_json() {
  local target_cwd="${1%/}"
  [[ -z "$target_cwd" ]] && return 1
  local session_file=""
  session_file="$(resolve_herdr_session_file || true)"
  [[ -z "$session_file" || ! -f "$session_file" ]] && return 1

  awk -v target="$target_cwd" '
    /"id"[[:space:]]*:[[:space:]]*"w[^"]+"/ {
      line = $0
      sub(/.*"id"[[:space:]]*:[[:space:]]*"/, "", line)
      sub(/".*/, "", line)
      current_workspace = line
    }
    /"(identity_cwd|checkout_path|cwd)"[[:space:]]*:[[:space:]]*"/ {
      path_line = $0
      sub(/.*:[[:space:]]*"/, "", path_line)
      sub(/".*/, "", path_line)
      gsub(/\\\\/, "/", path_line)
      sub(/\/$/, "", path_line)
      if (current_workspace != "" && length(path_line) > 1) {
        if (target == path_line || index(target "/", path_line "/") == 1 || index(path_line "/", target "/") == 1) {
          if (length(path_line) > best_length) {
            best_length = length(path_line)
            best_workspace = current_workspace
          }
        }
      }
    }
    END {
      if (best_workspace != "") {
        print best_workspace
      }
    }
  ' "$session_file" 2>/dev/null
}

json_escape_string() {
  local raw_value="${1:-}"
  raw_value="${raw_value//\\/\\\\}"
  raw_value="${raw_value//\"/\\\"}"
  raw_value="${raw_value//$'\n'/ }"
  raw_value="${raw_value//$'\r'/}"
  raw_value="${raw_value//$'\t'/ }"
  printf '%s' "$raw_value"
}

detect_server_kind_from_command() {
  local command_line="$1"
  if [[ "$command_line" =~ dev-servers\.(sh|ps1)|herdr-dev-servers ]]; then
    return 1
  fi
  if [[ "$command_line" =~ (^|[[:space:]\"\'/])dotnet(\.exe)?[\"\']?[[:space:]]+[\"\']?(run|watch)[\"\']?([[:space:]]|$) ]]; then
    printf 'dotnet'
    return 0
  fi
  if [[ "$command_line" =~ (^|[[:space:]\"\'/])pnpm(\.cjs|\.js|\.cmd|\.exe|\.ps1)?[\"\']?[[:space:]]+((--filter|-F|--dir|-C|--workspace-root)[[:space:]]+[^[:space:]]+[[:space:]]+)*([\"\']?run[\"\']?[[:space:]]+)?[\"\']?dev[\"\']?([[:space:]]|$) ]]; then
    printf 'pnpm'
    return 0
  fi
  if [[ "$command_line" =~ (^|[[:space:]\"\'/])(npm(\.cmd|\.exe|\.ps1)?|npm-cli\.js)[\"\']?[[:space:]]+((--prefix|-C|--workspace|-w)[[:space:]]+[^[:space:]]+[[:space:]]+)*[\"\']?run(-script)?[\"\']?[[:space:]]+[\"\']?dev[\"\']?([[:space:]]|$) ]]; then
    printf 'npm'
    return 0
  fi
  return 1
}

resolve_process_cwd() {
  local target_pid="$1"
  if [[ -L "/proc/${target_pid}/cwd" ]]; then
    readlink "/proc/${target_pid}/cwd" 2>/dev/null && return 0
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -a -p "$target_pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n1
    return 0
  fi
  return 1
}

capture_listening_sockets_table() {
  if command -v ss >/dev/null 2>&1; then
    printf 'ss\n'
    ss -tlnp 2>/dev/null || true
    return 0
  fi
  if command -v lsof >/dev/null 2>&1; then
    printf 'lsof\n'
    lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null || true
    return 0
  fi
}

collect_listening_ports_for_pids() {
  local pid_list_regex="$1"
  local listening_sockets_table="${2:-}"
  [[ -z "$pid_list_regex" ]] && return 0

  if [[ -z "${2+x}" ]]; then
    listening_sockets_table="$(capture_listening_sockets_table)"
  fi
  [[ -z "$listening_sockets_table" ]] && return 0

  local tool_tag="${listening_sockets_table%%$'\n'*}"
  local table_body="${listening_sockets_table#*$'\n'}"
  [[ "$table_body" == "$listening_sockets_table" ]] && return 0

  if [[ "$tool_tag" == "ss" ]]; then
    awk -v pid_regex="^(${pid_list_regex})$" '
      /LISTEN/ {
        port = $4
        sub(/^.*:/, "", port)
        while (match($0, /pid=[0-9]+/)) {
          pid_token = substr($0, RSTART + 4, RLENGTH - 4)
          if (pid_token ~ pid_regex && port ~ /^[0-9]+$/) {
            print port
          }
          $0 = substr($0, RSTART + RLENGTH)
        }
      }
    ' <<< "$table_body" | sort -n -u
    return 0
  fi

  if [[ "$tool_tag" == "lsof" ]]; then
    awk -v pid_regex="^(${pid_list_regex})$" '
      NR > 1 && $2 ~ pid_regex {
        port = $9
        sub(/^.*:/, "", port)
        if (port ~ /^[0-9]+$/) {
          print port
        }
      }
    ' <<< "$table_body" | sort -n -u
    return 0
  fi
}

# Collect descendant PIDs (one per line) for a given root PID.
# Contract: uses the caller's `children_by_pid` associative array when populated,
# falling back to a fresh `ps -eo pid=,ppid=` snapshot for standalone callers.
collect_descendant_pids_for_root() {
  local root_pid="$1"
  [[ -z "$root_pid" || ! "$root_pid" =~ ^[0-9]+$ ]] && return 0

  if ! declare -p children_by_pid >/dev/null 2>&1; then
    local process_table
    process_table="$(ps -eo pid=,ppid= 2>/dev/null || true)"
    declare -A children_by_pid=()
    local process_id parent_process_id
    while read -r process_id parent_process_id; do
      [[ -z "$process_id" || ! "$process_id" =~ ^[0-9]+$ ]] && continue
      if [[ -n "$parent_process_id" && "$parent_process_id" =~ ^[0-9]+$ ]]; then
        children_by_pid["$parent_process_id"]="${children_by_pid[$parent_process_id]:-} $process_id"
      fi
    done <<< "$process_table"
  fi

  local -a bfs_queue=("$root_pid")
  declare -A bfs_visited=(["$root_pid"]=1)
  local queue_head=0
  while (( queue_head < ${#bfs_queue[@]} )); do
    local current_node_pid="${bfs_queue[$queue_head]}"
    ((queue_head++))
    local child_pid
    for child_pid in ${children_by_pid[$current_node_pid]:-}; do
      if [[ -n "$child_pid" && -z "${bfs_visited[$child_pid]:-}" ]]; then
        bfs_visited["$child_pid"]=1
        bfs_queue+=("$child_pid")
        printf '%s\n' "$child_pid"
      fi
    done
  done
}

# Walk up the process tree from a starting PID to locate a Herdr shell registration file.
# Contract: reads parent PIDs from the caller's `parent_by_pid` associative array when populated,
# falling back to `ps -o ppid= -p "$current_pid"` if `parent_by_pid` is not populated.
find_shell_registration_for_pid() {
  local current_pid="$1"
  local hop=0
  while (( hop < 12 )) && [[ -n "$current_pid" && "$current_pid" =~ ^[0-9]+$ && "$current_pid" -gt 1 ]]; do
    local registration_file="${SHELLS_CACHE_DIR}/${current_pid}.json"
    if [[ -f "$registration_file" ]]; then
      cat "$registration_file" 2>/dev/null
      return 0
    fi
    local next_parent=""
    if declare -p parent_by_pid >/dev/null 2>&1; then
      next_parent="${parent_by_pid[$current_pid]:-}"
    else
      next_parent="$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' \t\r\n' || true)"
    fi
    if [[ -z "$next_parent" || "$next_parent" == "$current_pid" ]]; then
      break
    fi
    current_pid="$next_parent"
    ((hop++))
  done
  return 1
}

# Collect deduplicated root dev-server records as tab-delimited lines:
# root_pid\tkind\tworkspace_id\tpane_id\tpublic_pane\tports_csv\tcwd\tcommand_line\tdescendant_pids_csv
collect_deduplicated_dev_server_lines() {
  local process_table
  process_table="$(ps -eo pid=,ppid=,comm=,args= 2>/dev/null || true)"

  declare -A parent_by_pid=()
  declare -A children_by_pid=()
  declare -A command_by_pid=()
  declare -A matched_kind_by_pid=()
  local -a matched_pids=()
  local -a matched_kinds=()
  local -a matched_commands=()

  local process_id parent_process_id unused_process_name command_args
  while read -r process_id parent_process_id unused_process_name command_args; do
    [[ -z "$process_id" || ! "$process_id" =~ ^[0-9]+$ ]] && continue
    [[ "$process_id" == "$$" || "$process_id" == "${BASHPID:-$$}" ]] && continue
    parent_by_pid["$process_id"]="$parent_process_id"
    command_by_pid["$process_id"]="$command_args"
    if [[ -n "$parent_process_id" && "$parent_process_id" =~ ^[0-9]+$ ]]; then
      children_by_pid["$parent_process_id"]="${children_by_pid[$parent_process_id]:-} $process_id"
    fi
    local detected_kind=""
    if detected_kind="$(detect_server_kind_from_command "$command_args")"; then
      matched_pids+=("$process_id")
      matched_kinds+=("$detected_kind")
      matched_commands+=("$command_args")
      matched_kind_by_pid["$process_id"]="$detected_kind"
    fi
  done <<< "$process_table"

  local -a root_indices=()
  local index=0
  while (( index < ${#matched_pids[@]} )); do
    local candidate_pid="${matched_pids[$index]}"
    local has_matched_ancestor=0
    local current_parent="${parent_by_pid[$candidate_pid]:-}"
    local hop=0
    while (( hop < 16 )) && [[ -n "$current_parent" && "$current_parent" =~ ^[0-9]+$ && "$current_parent" -gt 1 ]]; do
      if [[ -n "${matched_kind_by_pid[$current_parent]:-}" ]]; then
        has_matched_ancestor=1
        break
      fi
      local next_parent="${parent_by_pid[$current_parent]:-}"
      [[ -z "$next_parent" || "$next_parent" == "$current_parent" ]] && break
      current_parent="$next_parent"
      ((hop++))
    done
    if (( has_matched_ancestor == 0 )); then
      root_indices+=("$index")
    fi
    ((index++))
  done

  local listening_sockets_table=""
  if (( ${#root_indices[@]} > 0 )); then
    listening_sockets_table="$(capture_listening_sockets_table)"
  fi

  local root_process_index
  for root_process_index in "${root_indices[@]:-}"; do
    [[ -z "$root_process_index" ]] && continue
    local root_pid="${matched_pids[$root_process_index]}"
    local server_kind="${matched_kinds[$root_process_index]}"
    local server_command="${matched_commands[$root_process_index]}"

    local -a child_pids=()
    local descendant_pid
    while read -r descendant_pid; do
      [[ -n "$descendant_pid" ]] && child_pids+=("$descendant_pid")
    done < <(collect_descendant_pids_for_root "$root_pid")

    local -a tree_pids=("$root_pid" "${child_pids[@]:-}")
    local pid_regex
    pid_regex="$(IFS='|'; printf '%s' "${tree_pids[*]}")"
    pid_regex="${pid_regex%|}"

    local -a server_ports=()
    local listening_port_number
    while read -r listening_port_number; do
      [[ -n "$listening_port_number" ]] && server_ports+=("$listening_port_number")
    done < <(collect_listening_ports_for_pids "$pid_regex" "$listening_sockets_table")

    local process_working_directory=""
    process_working_directory="$(resolve_process_cwd "$root_pid" || true)"

    local workspace_id=""
    local pane_id=""
    local public_pane=""
    local registration_json=""
    registration_json="$(find_shell_registration_for_pid "$root_pid" || true)"
    if [[ -n "$registration_json" ]]; then
      workspace_id="$(printf '%s' "$registration_json" | sed -n 's/.*"workspace_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
      pane_id="$(printf '%s' "$registration_json" | sed -n 's/.*"pane_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
      if [[ -z "$process_working_directory" ]]; then
        process_working_directory="$(printf '%s' "$registration_json" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
      fi
    fi

    if [[ -z "$workspace_id" && -n "$process_working_directory" ]]; then
      workspace_id="$(match_workspace_from_session_json "$process_working_directory" || true)"
    fi

    local ports_csv=""
    if (( ${#server_ports[@]} > 0 )); then
      ports_csv="$(IFS=,; printf '%s' "${server_ports[*]}")"
    fi

    local descendant_pids_csv=""
    if (( ${#child_pids[@]} > 0 )); then
      descendant_pids_csv="$(IFS=,; printf '%s' "${child_pids[*]}")"
    fi

    local sanitized_command="${server_command//$'\t'/ }"
    sanitized_command="${sanitized_command//$'\n'/ }"
    sanitized_command="${sanitized_command//$'\r'/}"
    local sanitized_cwd="${process_working_directory//$'\t'/ }"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$root_pid" \
      "$server_kind" \
      "$workspace_id" \
      "$pane_id" \
      "$public_pane" \
      "$ports_csv" \
      "$sanitized_cwd" \
      "$sanitized_command" \
      "$descendant_pids_csv"
  done
}

scan_dev_servers() {
  local collected_lines="${1:-}"
  if [[ -z "${1+x}" ]]; then
    collected_lines="$(collect_deduplicated_dev_server_lines)"
  fi

  local updated_unix_ms
  updated_unix_ms="$(($(date +%s) * 1000))"

  local -a servers_json_entries=()
  local server_count=0
  local field_separator=$'\x1f'
  local server_record_line

  while IFS= read -r server_record_line; do
    [[ -z "$server_record_line" ]] && continue
    local root_pid server_kind workspace_id pane_id public_pane ports_csv process_working_directory server_command descendant_pids_csv unused_trailing_field
    IFS="$field_separator" read -r root_pid server_kind workspace_id pane_id public_pane ports_csv process_working_directory server_command descendant_pids_csv unused_trailing_field <<< "${server_record_line//$'\t'/$field_separator}${field_separator}"
    [[ -z "$root_pid" ]] && continue

    ((server_count++))

    local escaped_command escaped_cwd escaped_workspace escaped_pane
    escaped_command="$(json_escape_string "$server_command")"
    escaped_cwd="$(json_escape_string "$process_working_directory")"
    escaped_workspace="$(json_escape_string "$workspace_id")"
    escaped_pane="$(json_escape_string "$pane_id")"

    local workspace_json="null"
    [[ -n "$escaped_workspace" ]] && workspace_json="\"${escaped_workspace}\""
    local pane_json="null"
    [[ -n "$escaped_pane" ]] && pane_json="\"${escaped_pane}\""
    local public_pane_json="null"
    [[ -n "$public_pane" && "$public_pane" =~ ^[0-9]+$ ]] && public_pane_json="$public_pane"
    local cwd_json="null"
    [[ -n "$escaped_cwd" ]] && cwd_json="\"${escaped_cwd}\""

    servers_json_entries+=("{\"id\":\"${server_kind}-${root_pid}\",\"rootPid\":${root_pid},\"childPids\":[${descendant_pids_csv}],\"listenerPids\":[],\"kind\":\"${server_kind}\",\"command\":\"${escaped_command}\",\"projectPath\":${cwd_json},\"cwd\":${cwd_json},\"ports\":[${ports_csv}],\"workspaceId\":${workspace_json},\"paneId\":${pane_json},\"publicPaneNumber\":${public_pane_json}}")
  done <<< "$collected_lines"

  local servers_array_content=""
  if (( ${#servers_json_entries[@]} > 0 )); then
    servers_array_content="$(IFS=,; printf '%s' "${servers_json_entries[*]}")"
  fi
  local snapshot_json="{\"updatedAtUnixMs\":${updated_unix_ms},\"servers\":[${servers_array_content}]}"

  local badge_text="DEV: OFF"
  if (( server_count > 0 )); then
    badge_text="DEV: ON"
  fi

  write_atomic_text_file "$SNAPSHOT_FILE" "$snapshot_json"
  write_atomic_text_file "$BADGE_FILE" "$badge_text"
  printf '%s\n' "$snapshot_json"
}

stop_process_tree() {
  local root_pid="$1"
  local descendant_pids_csv="${2:-}"
  [[ -z "$root_pid" || ! "$root_pid" =~ ^[0-9]+$ ]] && return 1

  local -a descendants=()
  if [[ -n "$descendant_pids_csv" ]]; then
    IFS=',' read -r -a descendants <<< "$descendant_pids_csv"
  else
    local descendant_pid
    while read -r descendant_pid; do
      [[ -n "$descendant_pid" ]] && descendants+=("$descendant_pid")
    done < <(collect_descendant_pids_for_root "$root_pid")
  fi

  log_dev_server_event "INFO" "stop_server" "rootPid=${root_pid} childCount=${#descendants[@]}"
  local child_pid
  for child_pid in "${descendants[@]:-}"; do
    [[ -n "$child_pid" ]] && kill -TERM "$child_pid" 2>/dev/null || true
  done
  kill -TERM "$root_pid" 2>/dev/null || true
  sleep 0.2
  for child_pid in "${descendants[@]:-}"; do
    if [[ -n "$child_pid" ]] && is_pid_alive "$child_pid"; then
      kill -KILL "$child_pid" 2>/dev/null || true
    fi
  done
  if is_pid_alive "$root_pid"; then
    kill -KILL "$root_pid" 2>/dev/null || true
  fi
  return 0
}

stop_workspace_servers() {
  local target_workspace="${1:-${HERDR_WORKSPACE_ID:-}}"
  local stopped_count=0
  local field_separator=$'\x1f'
  local server_record_line

  while IFS= read -r server_record_line; do
    [[ -z "$server_record_line" ]] && continue
    local root_pid server_kind server_workspace pane_id public_pane ports_csv process_working_directory server_command descendant_pids_csv unused_trailing_field
    IFS="$field_separator" read -r root_pid server_kind server_workspace pane_id public_pane ports_csv process_working_directory server_command descendant_pids_csv unused_trailing_field <<< "${server_record_line//$'\t'/$field_separator}${field_separator}"
    [[ -z "$root_pid" ]] && continue
    if [[ -n "$target_workspace" && "$target_workspace" != "--all" ]]; then
      [[ "$server_workspace" == "$target_workspace" ]] || continue
    fi
    stop_process_tree "$root_pid" "$descendant_pids_csv" && ((stopped_count++))
  done < <(collect_deduplicated_dev_server_lines)

  scan_dev_servers >/dev/null
  if (( stopped_count == 0 )) && [[ -n "$target_workspace" && "$target_workspace" != "--all" ]]; then
    log_dev_server_event "INFO" "stop_workspace_servers" "workspace=${target_workspace} stopped=0"
    printf 'STOPPED:0 (workspace=%s)\n' "$target_workspace"
    return 0
  fi
  local herdr_bin
  herdr_bin="$(resolve_herdr_binary || true)"
  if [[ -n "$herdr_bin" ]]; then
    "$herdr_bin" notification show "Dev Servers Stopped" --body "Stopped ${stopped_count} dev server(s)" --position top-right --sound none >/dev/null 2>&1 || true
  fi
  printf 'Stopped %d dev server(s) (workspace=%s).\n' "$stopped_count" "${target_workspace:-all}"
}

run_daemon() {
  local daemon_self_pid="${BASHPID:-$$}"
  write_atomic_text_file "$DAEMON_PID_FILE" "$daemon_self_pid"
  log_dev_server_event "INFO" "daemon_start" "started posix daemon"

  local observed_herdr=0
  if get_posix_herdr_pid >/dev/null 2>&1; then
    observed_herdr=1
  fi
  local previous_badge="DEV: OFF"

  cleanup_daemon() {
    trap - EXIT INT TERM HUP
    local recorded_pid=""
    [[ -f "$DAEMON_PID_FILE" ]] && recorded_pid="$(sed -n '1p' "$DAEMON_PID_FILE" 2>/dev/null | tr -d ' \t\r\n' || true)"
    if [[ "$recorded_pid" == "$daemon_self_pid" ]]; then
      rm -f "$DAEMON_PID_FILE" 2>/dev/null || true
      write_atomic_text_file "$BADGE_FILE" "DEV: OFF"
    fi
    log_dev_server_event "INFO" "daemon_stop" "stopped posix daemon"
    exit 0
  }
  trap cleanup_daemon EXIT INT TERM HUP

  while [[ -f "$DAEMON_PID_FILE" ]]; do
    local current_owner
    current_owner="$(sed -n '1p' "$DAEMON_PID_FILE" 2>/dev/null | tr -d ' \t\r\n' || true)"
    [[ "$current_owner" != "$daemon_self_pid" ]] && break

    if get_posix_herdr_pid >/dev/null 2>&1; then
      observed_herdr=1
    elif (( observed_herdr == 1 )); then
      break
    fi

    scan_dev_servers >/dev/null 2>&1 || true
    local current_badge
    current_badge="$(read_cached_badge_text)"
    if [[ "$current_badge" != "$previous_badge" && "$current_badge" == "DEV: ON" ]]; then
      local herdr_bin
      herdr_bin="$(resolve_herdr_binary || true)"
      if [[ -n "$herdr_bin" ]]; then
        "$herdr_bin" notification show "Dev Servers Active" --body "$current_badge" --position top-right --sound none >/dev/null 2>&1 || true
      fi
      log_dev_server_event "INFO" "badge_transition" "badge=${current_badge}"
    fi
    previous_badge="$current_badge"
    sleep 3 2>/dev/null || break
  done

  cleanup_daemon
}

TUI_SCRIPT="${SCRIPT_DIR}/dev-servers-tui.sh"
if [[ -f "$TUI_SCRIPT" ]]; then
  # shellcheck source=dev-servers-tui.sh
  source "$TUI_SCRIPT"
fi

action="${1:---open}"
case "$action" in
  --scan|scan)
    scan_dev_servers
    ;;
  --daemon|daemon)
    run_daemon
    ;;
  --open|open)
    open_dev_servers_board
    ;;
  --pane|pane)
    run_overlay_pane
    ;;
  --stop|stop)
    stop_workspace_servers "${2:-}"
    ;;
  --help|-h|help)
    printf 'usage: dev-servers.sh [--badge|--scan|--daemon|--open|--pane|--stop [workspaceId|--all]]\n'
    ;;
  *)
    printf 'usage: dev-servers.sh [--badge|--scan|--daemon|--open|--pane|--stop [workspaceId|--all]]\n' >&2
    exit 1
    ;;
esac
