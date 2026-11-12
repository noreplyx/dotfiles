#!/usr/bin/env bash
set -uo pipefail

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

target_path="${1:-}"
workspace_id="${2:-}"

if [[ -z "$target_path" || "$target_path" == "-" || "$workspace_id" == "-" ]]; then
  echo "No active git repositories found in Herdr workspaces."
  echo "Open a project with a Git repository in Herdr or create a worktree."
  exit 0
fi

expanded_path="$(expand_path "$target_path")"

if [[ ! -d "$expanded_path" ]]; then
  echo "Directory not found: $target_path"
  exit 0
fi

if ! git -C "$expanded_path" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not a git repository: $target_path"
  exit 0
fi
git -C "$expanded_path" log -1 --format="Commit: %h | Date: %cd (%cr) | Author: %an" 2>/dev/null || true
echo ""
git -C "$expanded_path" status -s --ignore-submodules=all 2>/dev/null || true
echo ""
git -C "$expanded_path" log -n 6 --graph --format="%C(auto)%h%d %s %C(cyan)(%cr)%C(reset)" --color=always 2>/dev/null || true
