#!/usr/bin/env bash
# TUI overlay board for the dotfiles.dev-servers Herdr plugin (POSIX).
# Sourced by dev-servers.sh.

open_dev_servers_board() {
  local herdr_bin
  herdr_bin="$(resolve_herdr_binary || true)"
  if [[ -n "$herdr_bin" ]]; then
    if "$herdr_bin" plugin pane open --plugin dotfiles.dev-servers --entrypoint board --placement overlay 2>/dev/null; then
      return 0
    fi
  fi
  if [[ ! ( -t 0 && -t 1 ) ]]; then
    scan_dev_servers >/dev/null 2>&1 || true
    if [[ -n "$herdr_bin" ]]; then
      local current_badge
      current_badge="$(read_cached_badge_text)"
      local notification_body="No active dotnet/pnpm/npm dev servers detected"
      [[ "$current_badge" != "DEV: OFF" ]] && notification_body="$current_badge"
      "$herdr_bin" notification show "Dev Servers" --body "$notification_body" --position top-right --sound none >/dev/null 2>&1 || true
    fi
    return 0
  fi
  run_overlay_pane
}

run_overlay_pane() {
  local accent_cyan=$'\033[38;2;125;207;255m'
  local accent_blue=$'\033[38;2;122;162;247m'
  local accent_green=$'\033[38;2;158;206;106m'
  local accent_yellow=$'\033[38;2;224;175;104m'
  local accent_magenta=$'\033[38;2;187;154;247m'
  local muted_gray=$'\033[38;2;86;95;137m'
  local selected_row_style=$'\033[48;2;41;46;66m\033[38;2;192;202;245m'
  local reset_style=$'\033[0m'

  local selected_index=0
  local field_separator=$'\x1f'

  while true; do
    local collected_lines
    collected_lines="$(collect_deduplicated_dev_server_lines)"
    scan_dev_servers "$collected_lines" >/dev/null 2>&1 || true

    local current_badge
    current_badge="$(read_cached_badge_text)"

    local -a server_lines=()
    local server_record_line
    while IFS= read -r server_record_line; do
      [[ -n "$server_record_line" ]] && server_lines+=("$server_record_line")
    done <<< "$collected_lines"

    local server_count="${#server_lines[@]}"
    if (( selected_index >= server_count )); then
      selected_index=$(( server_count > 0 ? server_count - 1 : 0 ))
    fi

    printf '\033[2J\033[H'
    printf '%s================================================================================%s\n' "$accent_cyan" "$reset_style"
    printf '  %sHERDR DEV SERVERS%s  %s|  Status: %s  |  Updated: %s%s\n' "$accent_blue" "$reset_style" "$muted_gray" "$current_badge" "$(date +%H:%M:%S)" "$reset_style"
    printf '%s================================================================================%s\n\n' "$accent_cyan" "$reset_style"

    printf '  %s%-3s %-12s %-6s %-8s %-8s %-12s %-14s %s%s\n' "$accent_magenta" "#" "Workspace" "Pane" "Root PID" "Type" "Ports" "Project" "Command" "$reset_style"
    printf '  %s------------------------------------------------------------------------------%s\n' "$muted_gray" "$reset_style"

    local selected_pid=""
    local selected_descendants=""
    local selected_workspace=""
    local selected_pane=""

    if (( server_count == 0 )); then
      printf '  %sNo active dotnet run, pnpm run dev, or npm run dev servers detected.%s\n' "$muted_gray" "$reset_style"
    else
      local row_index=0
      while (( row_index < server_count )); do
        local root_pid server_kind workspace_id pane_id public_pane ports_csv process_working_directory server_command descendant_pids_csv unused_trailing_field
        IFS="$field_separator" read -r root_pid server_kind workspace_id pane_id public_pane ports_csv process_working_directory server_command descendant_pids_csv unused_trailing_field <<< "${server_lines[$row_index]//$'\t'/$field_separator}${field_separator}"

        local pane_display="${pane_id:--}"
        [[ -n "$public_pane" ]] && pane_display="#${public_pane}"

        local ports_display="starting..."
        if [[ -n "$ports_csv" ]]; then
          ports_display=":${ports_csv//,/ :}"
        fi

        local project_folder_name="${process_working_directory##*/}"
        local selector_glyph=" "
        local row_style="$accent_green"
        [[ -z "$ports_csv" ]] && row_style="$accent_yellow"

        if (( row_index == selected_index )); then
          selector_glyph=">"
          row_style="$selected_row_style"
          selected_pid="$root_pid"
          selected_descendants="$descendant_pids_csv"
          selected_workspace="$workspace_id"
          selected_pane="$pane_id"
        fi

        printf '  %s%-3s %-12s %-6s %-8s %-8s %-12.12s %-14.14s %.24s%s\n' \
          "$row_style" \
          "${selector_glyph}$((row_index + 1))" \
          "${workspace_id:--}" \
          "$pane_display" \
          "$root_pid" \
          "$server_kind" \
          "$ports_display" \
          "${project_folder_name:--}" \
          "$server_command" \
          "$reset_style"
        ((row_index++))
      done
    fi

    printf '\n  %s[j/Down]%s Next  %s[Enter]%s Focus Workspace  %s[k/x]%s Kill Server Tree  %s[r]%s Refresh  %s[q/Esc]%s Close\n' \
      "$accent_cyan" "$reset_style" "$accent_cyan" "$reset_style" "$accent_cyan" "$reset_style" "$accent_cyan" "$reset_style" "$accent_cyan" "$reset_style"

    local key_pressed=""
    if IFS= read -rsn1 -t 3 key_pressed 2>/dev/null; then
      if [[ "$key_pressed" == $'\e' ]]; then
        local escape_seq=""
        if IFS= read -rsn2 -t 0.05 escape_seq 2>/dev/null; then
          case "$escape_seq" in
            "[A")
              (( selected_index > 0 )) && ((selected_index--))
              ;;
            "[B")
              (( selected_index < server_count - 1 )) && ((selected_index++))
              ;;
          esac
          continue
        fi
        return 0
      fi
      case "$key_pressed" in
        q|Q)
          return 0
          ;;
        j|J)
          (( selected_index < server_count - 1 )) && ((selected_index++))
          ;;
        "")
          if [[ -n "$selected_workspace" && "$selected_workspace" != "-" ]]; then
            local herdr_bin
            herdr_bin="$(resolve_herdr_binary || true)"
            if [[ -n "$herdr_bin" ]]; then
              "$herdr_bin" workspace focus "$selected_workspace" >/dev/null 2>&1 || true
              if [[ -n "$selected_pane" && "$selected_pane" != "-" ]]; then
                "$herdr_bin" pane focus "$selected_pane" >/dev/null 2>&1 || \
                  "$herdr_bin" agent focus "$selected_pane" >/dev/null 2>&1 || true
              fi
              return 0
            fi
          fi
          ;;
        k|K|x|X)
          if [[ -n "$selected_pid" ]]; then
            stop_process_tree "$selected_pid" "$selected_descendants"
          fi
          ;;
        r|R)
          ;;
      esac
    fi
  done
}
