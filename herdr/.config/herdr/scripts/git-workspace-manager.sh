#!/usr/bin/env bash
# Git Workspace Manager for Herdr (prefix+o).
# Interactive fzf overlay to list, preview, switch, push, pull, and rebase Git workspaces and worktrees.
set -euo pipefail

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
  if command -v pwsh.exe >/dev/null 2>&1; then
    printf 'pwsh.exe'
    return 0
  fi
  if command -v powershell.exe >/dev/null 2>&1; then
    printf 'powershell.exe'
    return 0
  fi
  if command -v pwsh >/dev/null 2>&1; then
    printf 'pwsh'
    return 0
  fi
  return 1
}

PLATFORM="$(detect_platform)"

if [[ "$PLATFORM" == "windows" && "${HERDR_GIT_WORKSPACE_POSIX:-0}" != "1" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PS1_SCRIPT="${SCRIPT_DIR}/git-workspace-manager.ps1"
  windows_powershell_script_path="$PS1_SCRIPT"
  if command -v cygpath >/dev/null 2>&1; then
    windows_powershell_script_path="$(cygpath -w "$PS1_SCRIPT" 2>/dev/null || printf '%s' "$PS1_SCRIPT")"
  fi
  powershell_binary="$(resolve_powershell || true)"
  if [[ -n "$powershell_binary" && -f "$PS1_SCRIPT" ]]; then
    case "${1:-}" in
      --list)
        exec "$powershell_binary" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$windows_powershell_script_path" -Mode List
        ;;
      --preview)
        shift
        exec "$powershell_binary" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$windows_powershell_script_path" -Mode Preview -Path "${1:-.}" -WorkspaceId "${2:-}"
        ;;
      --push)
        shift
        exec "$powershell_binary" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$windows_powershell_script_path" -Mode Push -Path "${1:-.}" -WorkspaceId "${2:-}"
        ;;
      --pull)
        shift
        exec "$powershell_binary" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$windows_powershell_script_path" -Mode Pull -Path "${1:-.}" -WorkspaceId "${2:-}"
        ;;
      --rebase)
        shift
        exec "$powershell_binary" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$windows_powershell_script_path" -Mode Rebase -Path "${1:-.}" -WorkspaceId "${2:-}"
        ;;
      --interactive|"")
        exec "$powershell_binary" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$windows_powershell_script_path" -Mode Interactive
        ;;
      *)
        exec "$powershell_binary" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$windows_powershell_script_path" "$@"
        ;;
    esac
  fi
fi

ensure_path() {
  local candidate_dirs=(
    "${HOME:-}/.local/bin"
    "${HOME:-}/bin"
    "${HOME:-}/.cargo/bin"
    "${HOME:-}/.fzf/bin"
    "${HOME:-}/.herdr/bin"
    "${HOME:-}/.herdr/packages/standalone/current"
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
  )

  local dirs_to_add=()
  for dir in "${candidate_dirs[@]}"; do
    if [[ -d "$dir" && ":${PATH:-}:" != *":$dir:"* ]]; then
      dirs_to_add+=("$dir")
    fi
  done

  local joined=""
  for dir in "${dirs_to_add[@]}"; do
    joined="${joined:+$joined:}$dir"
  done

  if [[ -n "$joined" ]]; then
    PATH="${joined}:${PATH:-}"
  fi
  export PATH
}

log_message() {
  local level="${1:-INFO}"
  local message="${2:-}"
  local cache_dir="${HOME:-}/.cache"
  if [[ -n "${HOME:-}" ]]; then
    mkdir -p "$cache_dir" 2>/dev/null || true
    local log_path="${cache_dir}/herdr-git-workspace.log"
    if [[ -f "$log_path" ]]; then
      local log_size=0
      log_size="$(stat -f %z "$log_path" 2>/dev/null || stat -c %s "$log_path" 2>/dev/null || printf '0')"
      if [[ "$log_size" =~ ^[0-9]+$ ]] && (( log_size > 524288 )); then
        mv -f "$log_path" "${log_path}.1" 2>/dev/null || true
      fi
    fi
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "timestamp")"
    printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >> "$log_path" 2>/dev/null || true
  fi
}

show_fatal_error() {
  local msg="$1"
  local detail="${2:-}"
  log_message "ERROR" "$msg $detail"
  printf '\n\033[1;31m [Git Workspace Manager Error]\033[0m\n' >&2
  printf '\033[0;31m %s\033[0m\n' "$msg" >&2
  if [[ -n "$detail" ]]; then
    printf '\033[0;90m Details: %s\033[0m\n' "$detail" >&2
  fi
  printf '\nPress Enter to exit...' >&2
  read -r _ || true
}

CACHED_HERDR_BIN=""
HERDR_CHECKED=0

resolve_herdr() {
  if [[ "$HERDR_CHECKED" -eq 1 ]]; then
    printf '%s' "$CACHED_HERDR_BIN"
    return 0
  fi
  local resolved=""
  if [[ -n "${HERDR_BIN_PATH:-}" && -f "${HERDR_BIN_PATH}" ]]; then
    resolved="$HERDR_BIN_PATH"
  elif command -v herdr >/dev/null 2>&1; then
    resolved="herdr"
  elif [[ -n "${HOME:-}" && -x "${HOME}/.herdr/packages/standalone/current/herdr" ]]; then
    resolved="${HOME}/.herdr/packages/standalone/current/herdr"
  elif [[ -n "${HOME:-}" && -x "${HOME}/.herdr/bin/herdr" ]]; then
    resolved="${HOME}/.herdr/bin/herdr"
  fi
  CACHED_HERDR_BIN="$resolved"
  HERDR_CHECKED=1
  if [[ -n "$resolved" ]]; then
    printf '%s' "$resolved"
    return 0
  fi
  return 1
}

notify_herdr() {
  local title="$1"
  local body="$2"
  local sound="${3:-none}"
  local herdr
  herdr="$(resolve_herdr || true)"
  if [[ -n "$herdr" ]]; then
    "$herdr" notification show "$title" --body "$body" --position top-right --sound "$sound" >/dev/null 2>&1 || true
  fi
}

expand_path() {
  local raw_path="${1:-}"
  if [[ -z "$raw_path" ]]; then
    printf ''
    return 0
  fi
  if [[ "$raw_path" == "~" ]]; then
    printf '%s' "${HOME:-}"
    return 0
  fi
  if [[ "$raw_path" == "~/"* || "$raw_path" == '~\\'* || "$raw_path" == '~\'* ]]; then
    printf '%s' "${HOME:-}/${raw_path:2}"
    return 0
  fi
  printf '%s' "$raw_path"
}

is_git_repository() {
  local raw_path="${1:-}"
  local expanded_path
  expanded_path="$(expand_path "$raw_path")"
  if [[ -z "$expanded_path" || ! -d "$expanded_path" ]]; then
    return 1
  fi
  if [[ -e "$expanded_path/.git" ]]; then
    return 0
  fi
  git -C "$expanded_path" rev-parse --git-dir >/dev/null 2>&1
}

get_git_base_branch() {
  local target_path="$1"
  local candidate
  for candidate in "origin/main" "origin/master" "main" "master"; do
    if git -C "$target_path" rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

format_worktree_entry() {
  local ws_name="$1"
  local ws_id="$2"
  local wt_id="$3"
  local wt_path="$4"

  [[ -z "$ws_name" ]] && ws_name="default"
  [[ -z "$ws_id" ]] && ws_id="-"
  [[ -z "$wt_id" ]] && wt_id="-"

  local expanded_path
  expanded_path="$(expand_path "$wt_path")"
  if [[ ! -d "$expanded_path" ]]; then
    return 0
  fi

  local status_output
  status_output="$(git -C "$expanded_path" status --porcelain=v2 --branch --ignore-submodules=all -unormal 2>/dev/null)" || return 0

  local raw_branch=""
  local oid=""
  local has_upstream=0
  local ahead=0
  local behind=0
  local dirty=""

  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" =~ ^#[[:space:]]*branch\.head[[:space:]]+(.*)$ ]]; then
      raw_branch="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^#[[:space:]]*branch\.oid[[:space:]]+(.*)$ ]]; then
      oid="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^#[[:space:]]*branch\.ab[[:space:]]+\+([0-9]+)[[:space:]]+-([0-9]+) ]]; then
      has_upstream=1
      ahead="${BASH_REMATCH[1]}"
      behind="${BASH_REMATCH[2]}"
    elif [[ -n "$line" && "$line" != \#* ]]; then
      dirty="*"
    fi
  done <<< "$status_output"

  local is_detached_or_initial=0
  local branch="$raw_branch"
  if [[ -z "$raw_branch" || "$raw_branch" == "(detached)" || "$oid" == "(initial)" ]]; then
    is_detached_or_initial=1
    if [[ -n "$oid" && "$oid" != "(initial)" ]]; then
      branch="${oid:0:7}"
    else
      branch="unknown"
    fi
  fi

  local push_count=0
  local pull_count=0
  local rebase_count=0

  if [[ "$is_detached_or_initial" -eq 0 ]]; then
    local base_branch
    base_branch="$(get_git_base_branch "$expanded_path" || true)"
    local base_name="${base_branch#origin/}"
    local is_on_base=0
    if [[ -n "$base_branch" && ( "$branch" == "$base_name" || "$branch" == "$base_branch" ) ]]; then
      is_on_base=1
    fi

    local left_count=0
    local right_count=0
    if [[ -n "$base_branch" ]] && { [[ "$has_upstream" -eq 0 ]] || [[ "$is_on_base" -eq 0 ]]; }; then
      local lr_counts=""
      lr_counts="$(git -C "$expanded_path" rev-list --left-right --count "${base_branch}...HEAD" 2>/dev/null || true)"
      if [[ -n "$lr_counts" ]]; then
        read -r left_count right_count <<< "$lr_counts"
        [[ "$left_count" =~ ^[0-9]+$ ]] || left_count=0
        [[ "$right_count" =~ ^[0-9]+$ ]] || right_count=0
      fi
    fi

    if [[ "$has_upstream" -eq 1 ]]; then
      push_count="$ahead"
      pull_count="$behind"
    else
      pull_count=0
      push_count="$right_count"
    fi

    if [[ "$is_on_base" -eq 1 || -z "$base_branch" ]]; then
      rebase_count=0
    else
      rebase_count="$left_count"
    fi
  fi

  local dirty_str=""
  [[ -n "$dirty" ]] && dirty_str=" *"

  local wt_dir
  wt_dir="$(basename "$expanded_path")"
  [[ -z "$wt_dir" ]] && wt_dir="$expanded_path"

  local ws_prefix=""
  if [[ -n "$ws_name" && "$ws_name" != [Dd][Ee][Ff][Aa][Uu][Ll][Tt] && "$ws_name" != "-" ]]; then
    ws_prefix="[$ws_name]  "
  fi
  printf '%s%s  (%s)  [push:%s | pull:%s | rebase:%s]%s\t%s\t%s\t%s\n' "$ws_prefix" "$wt_dir" "$branch" "$push_count" "$pull_count" "$rebase_count" "$dirty_str" "$ws_id" "$wt_id" "$expanded_path"
}

action_list() {
  ensure_path
  local herdr
  herdr="$(resolve_herdr || true)"
  local parsed=0

  log_message "INFO" "action_list started (Herdr: ${herdr:-none})"

  if [[ -n "$herdr" ]]; then
    local ws_json wt_json
    ws_json="$("$herdr" workspace list --json 2>/dev/null || true)"
    wt_json="$("$herdr" worktree list --json 2>/dev/null || true)"

    local raw_entries=""
    if [[ -n "$ws_json" || -n "$wt_json" ]]; then
      if command -v python3 >/dev/null 2>&1; then
        raw_entries="$(python3 -c '
import json, sys, os

def get_items(raw, key):
    if not raw or not raw.strip():
        return []
    try:
        data = json.loads(raw)
    except Exception:
        return []
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        result_node = data.get("result")
        if isinstance(result_node, list):
            return result_node
        if isinstance(result_node, dict):
            if key in result_node and isinstance(result_node[key], list):
                return result_node[key]
            for alt in ["data", "items"]:
                if alt in result_node and isinstance(result_node[alt], list):
                    return result_node[alt]
            if "id" in result_node:
                return [result_node]
        if key in data and isinstance(data[key], list):
            return data[key]
        for alt in ["data", "items"]:
            if alt in data and isinstance(data[alt], list):
                return data[alt]
        if "id" in data:
            return [data]
    return []

def get_prop(obj, keys, default=""):
    if not isinstance(obj, dict):
        return default
    for k in keys:
        v = obj.get(k)
        if v is not None and str(v).strip():
            return str(v).strip()
    return default

ws_raw = sys.argv[1] if len(sys.argv) > 1 else ""
wt_raw = sys.argv[2] if len(sys.argv) > 2 else ""

workspaces = get_items(ws_raw, "workspaces")
worktrees = get_items(wt_raw, "worktrees")

ws_map = {}
entries = {}

path_keys = ["cwd", "path", "directory", "root", "folder", "location", "workdir", "working_directory", "workingDirectory"]
id_keys = ["id", "workspace_id", "workspaceId", "workspace", "uuid"]
name_keys = ["name", "title", "label"]

for workspace_item in workspaces:
    if not isinstance(workspace_item, dict):
        continue
    w_id = get_prop(workspace_item, id_keys)
    w_name = get_prop(workspace_item, name_keys, w_id or "default")
    if w_id:
        ws_map[w_id] = w_name
    w_path = get_prop(workspace_item, path_keys)
    if w_path:
        expanded_path = os.path.expanduser(w_path)
        normalized_path_key = os.path.normcase(os.path.abspath(expanded_path))
        if normalized_path_key not in entries:
            entries[normalized_path_key] = [w_name, w_id or "-", "-", expanded_path]

for worktree_item in worktrees:
    if not isinstance(worktree_item, dict):
        continue
    t_id = get_prop(worktree_item, ["id", "worktree_id", "worktreeId"])
    w_id = get_prop(worktree_item, ["workspace_id", "workspaceId", "workspace"])
    w_name = ws_map.get(w_id, w_id or "default")
    t_path = get_prop(worktree_item, path_keys)
    if t_path:
        expanded_path = os.path.expanduser(t_path)
        normalized_path_key = os.path.normcase(os.path.abspath(expanded_path))
        if normalized_path_key in entries:
            entries[normalized_path_key][2] = t_id or "-"
            if (not entries[normalized_path_key][1] or entries[normalized_path_key][1] == "-") and w_id:
                entries[normalized_path_key][1] = w_id
        else:
            entries[normalized_path_key] = [w_name, w_id or "-", t_id or "-", expanded_path]

for item in entries.values():
    print(f"{item[0]}\t{item[1]}\t{item[2]}\t{item[3]}")
' "$ws_json" "$wt_json" 2>/dev/null || true)"
      elif command -v node >/dev/null 2>&1; then
        raw_entries="$(node -e '
const os = require("os");
const path = require("path");

function expandHome(rawPath) {
  if (!rawPath) return "";
  if (rawPath === "~") return os.homedir();
  if (rawPath.startsWith("~/") || rawPath.startsWith("~\\")) return path.join(os.homedir(), rawPath.slice(2));
  return rawPath;
}

function getItems(raw, key) {
  if (!raw || !raw.trim()) return [];
  let data;
  try { data = JSON.parse(raw); } catch (e) { return []; }
  if (Array.isArray(data)) return data;
  if (data && typeof data === "object") {
    const resultNode = data.result;
    if (Array.isArray(resultNode)) return resultNode;
    if (resultNode && typeof resultNode === "object") {
      if (Array.isArray(resultNode[key])) return resultNode[key];
      if (Array.isArray(resultNode.data)) return resultNode.data;
      if (Array.isArray(resultNode.items)) return resultNode.items;
      if (resultNode.id) return [resultNode];
    }
    if (Array.isArray(data[key])) return data[key];
    if (Array.isArray(data.data)) return data.data;
    if (Array.isArray(data.items)) return data.items;
    if (data.id) return [data];
  }
  return [];
}

function getProp(obj, keys, defVal = "") {
  if (!obj || typeof obj !== "object") return defVal;
  for (const k of keys) {
    if (obj[k] !== undefined && obj[k] !== null && String(obj[k]).trim()) {
      return String(obj[k]).trim();
    }
  }
  return defVal;
}

const pathKeys = ["cwd", "path", "directory", "root", "folder", "location", "workdir", "working_directory", "workingDirectory"];
const idKeys = ["id", "workspace_id", "workspaceId", "workspace", "uuid"];
const nameKeys = ["name", "title", "label"];

const ws = getItems(process.argv[1] || "", "workspaces");
const wt = getItems(process.argv[2] || "", "worktrees");

const wsMap = {};
const entries = new Map();

for (const workspaceItem of ws) {
  if (!workspaceItem || typeof workspaceItem !== "object") continue;
  const wId = getProp(workspaceItem, idKeys);
  const wName = getProp(workspaceItem, nameKeys, wId || "default");
  if (wId) wsMap[wId] = wName;
  const wPath = getProp(workspaceItem, pathKeys);
  if (wPath) {
    const expandedPath = expandHome(wPath);
    const normalizedPathKey = path.resolve(expandedPath).toLowerCase();
    if (!entries.has(normalizedPathKey)) {
      entries.set(normalizedPathKey, [wName, wId || "-", "-", expandedPath]);
    }
  }
}

for (const worktreeItem of wt) {
  if (!worktreeItem || typeof worktreeItem !== "object") continue;
  const tId = getProp(worktreeItem, ["id", "worktree_id", "worktreeId"]);
  const wId = getProp(worktreeItem, ["workspace_id", "workspaceId", "workspace"]);
  const wName = wsMap[wId] || wId || "default";
  const tPath = getProp(worktreeItem, pathKeys);
  if (tPath) {
    const expandedPath = expandHome(tPath);
    const normalizedPathKey = path.resolve(expandedPath).toLowerCase();
    if (entries.has(normalizedPathKey)) {
      const existing = entries.get(normalizedPathKey);
      existing[2] = tId || "-";
      if ((!existing[1] || existing[1] === "-") && wId) existing[1] = wId;
    } else {
      entries.set(normalizedPathKey, [wName, wId || "-", tId || "-", expandedPath]);
    }
  }
}

for (const item of entries.values()) {
  console.log(`${item[0]}\t${item[1]}\t${item[2]}\t${item[3]}`);
}
' "$ws_json" "$wt_json" 2>/dev/null || true)"
      elif command -v jq >/dev/null 2>&1; then
        local ws_payload="${ws_json:-{}}"
        local wt_payload="${wt_json:-{}}"
        raw_entries="$(jq -rn --argjson ws "$ws_payload" --argjson wt "$wt_payload" '
          def extract(k):
            if type == "array" then .
            elif type == "object" then
              (.result // .) |
              if type == "array" then .
              elif type == "object" then (.[k] // .data // .items // [])
              else [] end
            else [] end;

          (($ws | extract("workspaces") | map(select(type == "object") | {((.id // .workspace_id // .workspaceId // "") | tostring): (.name // .title // .label // .id // "default")}) | add) // {}) as $ws_map |
          (
            reduce (
              ($ws | extract("workspaces")[]? | select(type == "object") | {
                name: (.name // .title // .label // .id // "default"),
                ws_id: ((.id // .workspace_id // .workspaceId // "-") | tostring),
                wt_id: "-",
                path: (.cwd // .path // .directory // .root // .folder // .location // .workdir // .working_directory // .workingDirectory // "")
              }),
              ($wt | extract("worktrees")[]? | select(type == "object") |
                ((.workspace_id // .workspaceId // .workspace // "") | tostring) as $wid |
                {
                  name: ($ws_map[$wid] // (if $wid != "" then $wid else "default" end)),
                  ws_id: (if $wid != "" then $wid else "-" end),
                  wt_id: ((.id // .worktree_id // .worktreeId // "-") | tostring),
                  path: (.cwd // .path // .directory // .root // .folder // .location // .workdir // .working_directory // .workingDirectory // "")
                }
              )
            ) as $item ({};
              if ($item.path // "") == "" then .
              elif has($item.path) then
                .[$item.path].wt_id = (if $item.wt_id != "-" and $item.wt_id != "" then $item.wt_id else .[$item.path].wt_id end) |
                .[$item.path].ws_id = (if (.[$item.path].ws_id == "-" or .[$item.path].ws_id == "") and $item.ws_id != "-" and $item.ws_id != "" then $item.ws_id else .[$item.path].ws_id end)
              else
                .[$item.path] = {
                  name: (if ($item.name // "") != "" then $item.name else "default" end),
                  ws_id: (if ($item.ws_id // "") != "" then $item.ws_id else "-" end),
                  wt_id: (if ($item.wt_id // "") != "" then $item.wt_id else "-" end),
                  path: $item.path
                }
              end
            )
          ) |
          .[] |
          [.name, .ws_id, .wt_id, .path] |
          @tsv
        ' 2>/dev/null || true)"
      fi
    fi

    if [[ -n "$raw_entries" ]]; then
      while IFS=$'\t' read -r ws_name ws_id wt_id wt_path; do
        [[ -z "$wt_path" ]] && continue
        local expanded_path
        expanded_path="$(expand_path "$wt_path")"
        if is_git_repository "$expanded_path"; then
          parsed=1
          format_worktree_entry "$ws_name" "$ws_id" "$wt_id" "$expanded_path"
        fi
      done <<< "$raw_entries"
    fi

    # Fallback to plain text output if JSON parsing yielded nothing
    if [[ "$parsed" -eq 0 ]]; then
      local workspace_list_text worktree_list_text
      workspace_list_text="$("$herdr" workspace list 2>/dev/null || true)"
      worktree_list_text="$("$herdr" worktree list 2>/dev/null || true)"

      if [[ -n "$workspace_list_text" || -n "$worktree_list_text" ]]; then
        local ws_map_ids=()
        local ws_map_names=()
        local candidate_paths=()
        local candidate_ws_names=()
        local candidate_ws_ids=()
        local candidate_wt_ids=()

        if [[ -n "$workspace_list_text" ]]; then
          while IFS= read -r workspace_line; do
            workspace_line="${workspace_line%$'\r'}"
            [[ -z "$workspace_line" || "$workspace_line" =~ ^[[:space:]]*ID || "$workspace_line" =~ ^[[:space:]]*-+ ]] && continue
            local current_workspace_id="" current_workspace_name="" current_workspace_path=""
            read -r current_workspace_id current_workspace_name current_workspace_path <<< "$workspace_line"
            if [[ -n "$current_workspace_id" ]]; then
              ws_map_ids+=("$current_workspace_id")
              ws_map_names+=("${current_workspace_name:-$current_workspace_id}")
            fi
            if [[ -n "$current_workspace_path" ]]; then
              local exp_ws_path
              exp_ws_path="$(expand_path "$current_workspace_path")"
              if is_git_repository "$exp_ws_path"; then
                local existing_idx=-1 idx=0
                for (( idx=0; idx<${#candidate_paths[@]}; idx++ )); do
                  if [[ "${candidate_paths[$idx]}" == "$exp_ws_path" ]]; then
                    existing_idx=$idx
                    break
                  fi
                done
                if (( existing_idx < 0 )); then
                  candidate_paths+=("$exp_ws_path")
                  candidate_ws_names+=("${current_workspace_name:-${current_workspace_id:-default}}")
                  candidate_ws_ids+=("${current_workspace_id:--}")
                  candidate_wt_ids+=("-")
                fi
              fi
            fi
          done <<< "$workspace_list_text"
        fi

        if [[ -n "$worktree_list_text" ]]; then
          while IFS= read -r worktree_line; do
            worktree_line="${worktree_line%$'\r'}"
            [[ -z "$worktree_line" || "$worktree_line" =~ ^[[:space:]]*ID || "$worktree_line" =~ ^[[:space:]]*-+ ]] && continue
            local worktree_id="" target_workspace_id="" worktree_path=""
            read -r worktree_id target_workspace_id worktree_path <<< "$worktree_line"
            if [[ -n "$worktree_path" ]]; then
              local exp_wt_path
              exp_wt_path="$(expand_path "$worktree_path")"
              if is_git_repository "$exp_wt_path"; then
                local display_workspace_name="$target_workspace_id"
                local map_idx=0
                for (( map_idx=0; map_idx<${#ws_map_ids[@]}; map_idx++ )); do
                  if [[ "${ws_map_ids[$map_idx]}" == "$target_workspace_id" ]]; then
                    display_workspace_name="${ws_map_names[$map_idx]}"
                    break
                  fi
                done
                [[ -z "$display_workspace_name" ]] && display_workspace_name="default"

                local existing_idx=-1 idx=0
                for (( idx=0; idx<${#candidate_paths[@]}; idx++ )); do
                  if [[ "${candidate_paths[$idx]}" == "$exp_wt_path" ]]; then
                    existing_idx=$idx
                    break
                  fi
                done
                if (( existing_idx >= 0 )); then
                  if [[ -n "$worktree_id" ]]; then
                    candidate_wt_ids[$existing_idx]="$worktree_id"
                  fi
                  if [[ "${candidate_ws_ids[$existing_idx]}" == "-" && -n "$target_workspace_id" ]]; then
                    candidate_ws_ids[$existing_idx]="$target_workspace_id"
                  fi
                else
                  candidate_paths+=("$exp_wt_path")
                  candidate_ws_names+=("$display_workspace_name")
                  candidate_ws_ids+=("${target_workspace_id:--}")
                  candidate_wt_ids+=("${worktree_id:--}")
                fi
              fi
            fi
          done <<< "$worktree_list_text"
        fi

        local entry_idx=0
        for (( entry_idx=0; entry_idx<${#candidate_paths[@]}; entry_idx++ )); do
          parsed=1
          format_worktree_entry "${candidate_ws_names[$entry_idx]}" "${candidate_ws_ids[$entry_idx]}" "${candidate_wt_ids[$entry_idx]}" "${candidate_paths[$entry_idx]}"
        done
      fi
    fi
  fi

  # Graceful fallback: current git repo if available
  if [[ "$parsed" -eq 0 ]]; then
    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$repo_root" ]]; then
      parsed=1
      format_worktree_entry "default" "default" "-" "$repo_root"
    fi
  fi

  # Placeholder line so fzf never receives empty stdin
  if [[ "$parsed" -eq 0 ]]; then
    log_message "WARN" "0 git repositories found; emitting placeholder line"
    printf '[No Git Workspaces Found]  No active git repositories found in Herdr workspaces\t-\t-\t-\n'
  fi
}

action_preview() {
  local target_path="${1:-.}"
  local workspace_id="${2:-}"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local preview_script="${script_dir}/git-workspace-manager-preview.sh"

  if [[ -f "$preview_script" ]]; then
    bash "$preview_script" "$target_path" "$workspace_id"
    return $?
  fi

  if [[ "$workspace_id" == "-" || "$target_path" == "-" || ( "$target_path" == "." && "$workspace_id" == "-" ) ]]; then
    echo "No active git repositories found in Herdr workspaces."
    echo "Open a project with a Git repository in Herdr or create a worktree."
    return 0
  fi

  local expanded_path
  expanded_path="$(expand_path "$target_path")"
  if [[ ! -d "$expanded_path" ]]; then
    echo "Directory not found: $target_path"
    return 1
  fi
  if ! git -C "$expanded_path" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Not a git repository: $target_path"
    return 1
  fi
  git -C "$expanded_path" log -1 --format="Commit: %h | Date: %cd (%cr) | Author: %an" 2>/dev/null || true
  echo ""
  git -C "$expanded_path" status -s --ignore-submodules=all
  echo ""
  git -C "$expanded_path" log -n 6 --graph --format="%C(auto)%h%d %s %C(cyan)(%cr)%C(reset)" --color=always 2>/dev/null || true
}

run_git_non_interactive() {
  GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never GIT_EDITOR=true git -c core.editor=true "$@"
}

VALIDATED_PATH=""
VALIDATED_REPO_NAME=""
VALIDATED_BRANCH=""

validate_git_worktree_branch() {
  local target_path="${1:-.}"
  local workspace_id="${2:-}"
  local action_label="${3:-Action}"
  local require_clean_tree="${4:-0}"

  VALIDATED_PATH=""
  VALIDATED_REPO_NAME=""
  VALIDATED_BRANCH=""

  if [[ "$workspace_id" == "-" || "$target_path" == "-" || -z "$target_path" ]]; then
    return 2
  fi

  local expanded_path
  expanded_path="$(expand_path "$target_path")"
  local repo_name
  repo_name="$(basename "$expanded_path")"
  if [[ ! -d "$expanded_path" ]] || ! is_git_repository "$expanded_path"; then
    notify_herdr "Git ${action_label} Failed" "Invalid git repository at $target_path" "none"
    return 1
  fi

  local current_branch
  current_branch="$(git -C "$expanded_path" branch --show-current 2>/dev/null || true)"
  if [[ -z "$current_branch" ]]; then
    notify_herdr "Git ${action_label} Failed" "Detached HEAD in $repo_name" "none"
    return 1
  fi

  if [[ "$require_clean_tree" -eq 1 ]]; then
    local dirty
    dirty="$(git -C "$expanded_path" status --porcelain 2>/dev/null || true)"
    if [[ -n "$dirty" ]]; then
      notify_herdr "Git ${action_label} Aborted" "Working tree is dirty in $repo_name" "none"
      return 1
    fi
  fi

  VALIDATED_PATH="$expanded_path"
  VALIDATED_REPO_NAME="$repo_name"
  VALIDATED_BRANCH="$current_branch"
  return 0
}

action_push() {
  local target_path="${1:-.}"
  local workspace_id="${2:-}"

  local validation_status=0
  validate_git_worktree_branch "$target_path" "$workspace_id" "Push" 0 || validation_status=$?
  if [[ "$validation_status" -eq 2 ]]; then
    return 0
  elif [[ "$validation_status" -ne 0 ]]; then
    return 1
  fi

  local expanded_path="$VALIDATED_PATH"
  local repo_name="$VALIDATED_REPO_NAME"
  local current_branch="$VALIDATED_BRANCH"

  notify_herdr "Git Push" "Pushing ${current_branch} in $repo_name..."

  local push_args=("-C" "$expanded_path" "push")
  if ! git -C "$expanded_path" rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
    push_args+=("-u" "origin" "$current_branch")
  fi

  if run_git_non_interactive "${push_args[@]}"; then
    notify_herdr "Git Push" "Pushed ${current_branch} successfully in $repo_name" "none"
  else
    notify_herdr "Git Push Failed" "Failed to push ${current_branch} in $repo_name" "none"
    return 1
  fi
}

action_pull() {
  local target_path="${1:-.}"
  local workspace_id="${2:-}"

  local validation_status=0
  validate_git_worktree_branch "$target_path" "$workspace_id" "Pull" 1 || validation_status=$?
  if [[ "$validation_status" -eq 2 ]]; then
    return 0
  elif [[ "$validation_status" -ne 0 ]]; then
    return 1
  fi

  local expanded_path="$VALIDATED_PATH"
  local repo_name="$VALIDATED_REPO_NAME"
  local current_branch="$VALIDATED_BRANCH"

  notify_herdr "Git Pull" "Pulling ${current_branch} in $repo_name..."

  if run_git_non_interactive -C "$expanded_path" pull --ff-only; then
    notify_herdr "Git Pull" "Pulled successfully in $repo_name" "none"
  else
    notify_herdr "Git Pull Failed" "Failed to pull in $repo_name" "none"
    return 1
  fi
}

action_rebase() {
  local target_path="${1:-.}"
  local workspace_id="${2:-}"

  local validation_status=0
  validate_git_worktree_branch "$target_path" "$workspace_id" "Rebase" 1 || validation_status=$?
  if [[ "$validation_status" -eq 2 ]]; then
    return 0
  elif [[ "$validation_status" -ne 0 ]]; then
    return 1
  fi

  local expanded_path="$VALIDATED_PATH"
  local repo_name="$VALIDATED_REPO_NAME"
  local current_branch="$VALIDATED_BRANCH"

  local base_branch
  base_branch="$(get_git_base_branch "$expanded_path" || true)"
  local base_name="${base_branch#origin/}"
  local target=""

  if [[ -n "$base_branch" && "$current_branch" != "$base_name" && "$current_branch" != "$base_branch" ]]; then
    target="$base_branch"
  elif git -C "$expanded_path" rev-parse --verify --quiet @{u} >/dev/null 2>&1; then
    target="@{u}"
  elif [[ -n "$base_branch" ]]; then
    target="$base_branch"
  else
    notify_herdr "Git Rebase Failed" "No suitable base or upstream branch found in $repo_name" "none"
    return 1
  fi

  notify_herdr "Git Rebase" "Rebasing ${current_branch} in $repo_name..."

  if run_git_non_interactive -C "$expanded_path" rebase "$target"; then
    notify_herdr "Git Rebase" "Rebased onto ${target} in $repo_name" "none"
  else
    git -C "$expanded_path" rebase --abort 2>/dev/null || true
    notify_herdr "Git Rebase Failed" "Rebase onto ${target} failed; aborted in $repo_name" "none"
    return 1
  fi
}

action_interactive() {
  ensure_path
  log_message "INFO" "Interactive mode started"

  if ! command -v git >/dev/null 2>&1; then
    show_fatal_error "git is required for interactive mode but was not found in PATH." "Please install Git or ensure it is available in PATH."
    exit 1
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    show_fatal_error "fzf is required for interactive mode but was not found in PATH." "Please install fzf (e.g. brew install fzf, apt install fzf, or scoop install fzf)."
    exit 1
  fi

  local script_path="${BASH_SOURCE[0]}"
  if [[ -f "$script_path" ]]; then
    script_path="$(cd "$(dirname "$script_path")" >/dev/null 2>&1 && pwd)/$(basename "$script_path")"
  fi

  local list_items=""
  list_items="$(action_list 2>/dev/null || true)"
  if [[ -z "$list_items" ]]; then
    list_items="[No Git Workspaces Found]  No active git repositories found in Herdr workspaces	-	-	-"
  fi

  local header="[Enter] Switch Worktree | [Alt-p] Push | [Alt-u] Pull | [Alt-r] Rebase | [Ctrl-r] Refresh | [Esc] Close"
  local preview_script
  preview_script="$(dirname "$script_path")/git-workspace-manager-preview.sh"
  local preview_cmd="\"$preview_script\" {4} {2}"
  local push_cmd="\"$script_path\" --push {4} {2} >/dev/null 2>&1"
  local pull_cmd="\"$script_path\" --pull {4} {2} >/dev/null 2>&1"
  local rebase_cmd="\"$script_path\" --rebase {4} {2} >/dev/null 2>&1"
  local list_cmd="\"$script_path\" --list"

  local fzf_exit_code=0
  local selected=""
  selected="$(printf '%s\n' "$list_items" | fzf \
    --delimiter=$'\t' \
    --with-nth=1 \
    --header="$header" \
    --preview="$preview_cmd" \
    --preview-window=right:55%:wrap \
    --bind "alt-p:execute-silent($push_cmd)+reload($list_cmd)" \
    --bind "alt-u:execute-silent($pull_cmd)+reload($list_cmd)" \
    --bind "alt-r:execute-silent($rebase_cmd)+reload($list_cmd)" \
    --bind "ctrl-r:reload($list_cmd)" \
    2>/dev/null)" || fzf_exit_code=$?

  if (( fzf_exit_code > 1 && fzf_exit_code != 130 )); then
    show_fatal_error "fzf exited with error code $fzf_exit_code."
    exit 1
  fi

  if [[ -z "$selected" ]]; then
    log_message "INFO" "fzf closed without selection; exiting"
    exit 0
  fi

  local display ws_id wt_id wt_path
  IFS=$'\t' read -r display ws_id wt_id wt_path <<< "$selected"

  if [[ "$ws_id" == "-" || "$display" == *"[No Git Workspaces Found]"* ]]; then
    log_message "INFO" "Placeholder selected; exiting without action"
    exit 0
  fi

  log_message "INFO" "Selected entry: ws_id='$ws_id', wt_id='$wt_id'"
  local herdr
  herdr="$(resolve_herdr || true)"
  if [[ -n "$herdr" ]]; then
    if [[ -n "$ws_id" && "$ws_id" != "default" && "$ws_id" != "-" ]]; then
      "$herdr" workspace focus "$ws_id" >/dev/null 2>&1 || true
    fi
    if [[ -n "$wt_id" && "$wt_id" != "default" && "$wt_id" != "-" ]]; then
      "$herdr" worktree focus "$wt_id" >/dev/null 2>&1 || true
    fi
  fi
}

case "${1:-}" in
  --list)
    action_list
    ;;
  --preview)
    shift
    action_preview "${1:-.}" "${2:-}"
    ;;
  --push)
    shift
    action_push "${1:-.}" "${2:-}"
    ;;
  --pull)
    shift
    action_pull "${1:-.}" "${2:-}"
    ;;
  --rebase)
    shift
    action_rebase "${1:-.}" "${2:-}"
    ;;
  --interactive|"")
    trap 'show_fatal_error "Unexpected error on line $LINENO in interactive mode"' ERR
    action_interactive
    ;;
  *)
    echo "Usage: $0 [--interactive|--list|--preview <path> [workspace_id]|--push <path> [workspace_id]|--pull <path> [workspace_id]|--rebase <path> [workspace_id]]" >&2
    exit 1
    ;;
esac
