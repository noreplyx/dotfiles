local M = {}

local uv = vim.uv or vim.loop

local excluded_build_and_dependency_directories = {
  [".git"] = true,
  node_modules = true,
  obj = true,
  ref = true,
}

local excluded_source_and_test_directories =
  vim.tbl_extend("force", {}, excluded_build_and_dependency_directories, { bin = true })

function M.is_searchable_test_directory(directory_name)
  return not excluded_source_and_test_directories[directory_name]
end

function M.append_unique_items(target_list, items_to_add)
  target_list = target_list or {}
  for _, item in ipairs(items_to_add) do
    if not vim.tbl_contains(target_list, item) then
      table.insert(target_list, item)
    end
  end
  return target_list
end

function M.resolve_netcoredbg_executable()
  local system_executable = vim.fn.exepath("netcoredbg")
  if system_executable ~= "" then
    return vim.fs.normalize(system_executable)
  end

  local is_windows = vim.fn.has("win32") == 1
  local executable_suffix = is_windows and ".exe" or ""
  local shim_suffix = is_windows and ".cmd" or ""
  local data_directory = vim.fn.stdpath("data")

  local candidate_paths = {
    data_directory .. "/mason/bin/netcoredbg" .. shim_suffix,
    data_directory .. "/mason/packages/netcoredbg/netcoredbg/netcoredbg" .. executable_suffix,
    data_directory .. "/mason/packages/netcoredbg/netcoredbg" .. executable_suffix,
  }

  for _, candidate_path in ipairs(candidate_paths) do
    if vim.fn.executable(candidate_path) == 1 then
      return vim.fs.normalize(candidate_path)
    end
  end

  return vim.fs.normalize(candidate_paths[#candidate_paths])
end

local function scan_files_pruned(root_directory, excluded_directories, file_predicate)
  local matched_files = {}
  local normalized_root = vim.fs.normalize(root_directory)
  if not uv.fs_stat(normalized_root) then
    return matched_files
  end

  local directory_queue = { normalized_root }
  while #directory_queue > 0 do
    local current_directory = table.remove(directory_queue)
    local scan_handle = uv.fs_scandir(current_directory)
    if scan_handle then
      while true do
        local entry_name, entry_type = uv.fs_scandir_next(scan_handle)
        if not entry_name then
          break
        end

        local entry_path = current_directory .. "/" .. entry_name
        local resolved_type = entry_type
        if not resolved_type then
          local stat = uv.fs_stat(entry_path)
          resolved_type = stat and stat.type or nil
        end

        if resolved_type == "directory" then
          if not excluded_directories[entry_name] then
            table.insert(directory_queue, entry_path)
          end
        elseif resolved_type == "file" then
          if file_predicate(entry_name, entry_path) then
            table.insert(matched_files, vim.fs.normalize(entry_path))
          end
        end
      end
    end
  end

  return matched_files
end

function M.find_dotnet_build_target(starting_path)
  local search_start = starting_path ~= "" and starting_path or vim.fn.getcwd()
  local upward_matches = vim.fs.find(function(file_name)
    return file_name:match("%.csproj$") ~= nil or file_name:match("%.slnx?$") ~= nil
  end, {
    upward = true,
    path = search_start,
    limit = 1,
  })

  if upward_matches[1] then
    return vim.fs.normalize(upward_matches[1])
  end

  local workspace_root = vim.fs.normalize(vim.fn.getcwd())
  local workspace_targets = scan_files_pruned(
    workspace_root,
    excluded_source_and_test_directories,
    function(file_name)
      return file_name:match("%.slnx?$") ~= nil or file_name:match("%.csproj$") ~= nil
    end
  )

  if workspace_targets[1] then
    table.sort(workspace_targets)
    return workspace_targets[1]
  end

  return workspace_root
end

function M.run_dotnet_debug_build(build_target, on_complete)
  local start_time_ns = uv.hrtime()
  vim.notify("Building .NET target (Debug): " .. build_target, vim.log.levels.INFO, { title = "C# Debugger" })

  vim.system(
    { "dotnet", "build", "-c", "Debug", build_target },
    { text = true },
    vim.schedule_wrap(function(build_result)
      local duration_ms = math.floor((uv.hrtime() - start_time_ns) / 1e6)

      if build_result.code ~= 0 then
        local error_output = vim.trim((build_result.stderr or "") .. "\n" .. (build_result.stdout or ""))
        local failure_message = string.format(
          "dotnet build failed (exit %d, %dms) for %s:\n%s",
          build_result.code,
          duration_ms,
          build_target,
          error_output
        )
        vim.notify(failure_message, vim.log.levels.ERROR, { title = "C# Debugger" })
        on_complete(false)
        return
      end

      vim.notify(
        string.format("dotnet build succeeded (%dms): %s", duration_ms, build_target),
        vim.log.levels.INFO,
        { title = "C# Debugger" }
      )
      on_complete(true)
    end)
  )
end

local function is_noise_assembly(file_name)
  local lower_name = file_name:lower()
  if lower_name == "testhost.dll" then
    return true
  end
  if lower_name:match("%.views%.dll$") or lower_name:match("%.precompiledviews%.dll$") then
    return true
  end
  return false
end

local function discover_projects(search_root)
  local project_files = scan_files_pruned(search_root, excluded_source_and_test_directories, function(file_name)
    return file_name:match("%.csproj$") ~= nil
  end)

  local project_names = {}
  local project_directories = {}
  for _, project_file in ipairs(project_files) do
    local base_name = vim.fn.fnamemodify(project_file, ":t:r")
    project_names[base_name:lower()] = true
    table.insert(project_directories, vim.fs.dirname(project_file))
  end

  return project_names, project_directories
end

function M.discover_debug_dll_candidates(search_root)
  local normalized_root = vim.fs.normalize(search_root)
  local known_project_names, project_directories = discover_projects(normalized_root)

  local candidate_files = {}
  if #project_directories > 0 then
    for _, project_directory in ipairs(project_directories) do
      local debug_output_directory = project_directory .. "/bin/Debug"
      local project_dlls = scan_files_pruned(
        debug_output_directory,
        excluded_build_and_dependency_directories,
        function(file_name)
          return file_name:lower():match("%.dll$") ~= nil and not is_noise_assembly(file_name)
        end
      )
      vim.list_extend(candidate_files, project_dlls)
    end
  else
    candidate_files = scan_files_pruned(
      normalized_root,
      excluded_build_and_dependency_directories,
      function(file_name, file_path)
        if not file_name:lower():match("%.dll$") or is_noise_assembly(file_name) then
          return false
        end
        return file_path:lower():find("/bin/debug/", 1, true) ~= nil
      end
    )
  end

  local prioritized_candidates = {}
  local fallback_candidates = {}

  for _, dll_path in ipairs(candidate_files) do
    local normalized_dll = vim.fs.normalize(dll_path)
    local assembly_base_name = vim.fn.fnamemodify(normalized_dll, ":t:r")
    local runtime_config_path = vim.fn.fnamemodify(normalized_dll, ":r") .. ".runtimeconfig.json"
    local has_runtime_config = uv.fs_stat(runtime_config_path) ~= nil
    local matches_project_name = known_project_names[assembly_base_name:lower()] == true

    if has_runtime_config or matches_project_name then
      table.insert(prioritized_candidates, normalized_dll)
    else
      table.insert(fallback_candidates, normalized_dll)
    end
  end

  local results = #prioritized_candidates > 0 and prioritized_candidates or fallback_candidates
  table.sort(results)
  return results
end

function M.resolve_search_root(build_target)
  if not uv.fs_stat(build_target) then
    return vim.fs.normalize(vim.fn.getcwd())
  end
  if vim.fn.isdirectory(build_target) == 1 then
    return vim.fs.normalize(build_target)
  end
  return vim.fs.normalize(vim.fs.dirname(build_target))
end

local function prompt_manual_dll_path(default_directory)
  local initial_path = vim.fs.normalize(default_directory) .. "/bin/Debug/"
  local user_input = vim.fn.input("Path to runnable .NET DLL: ", initial_path, "file")
  if user_input == nil or vim.trim(user_input) == "" then
    return nil
  end
  return vim.fs.normalize(user_input)
end

function M.select_and_build_dotnet_dll()
  local dap = require("dap")

  return coroutine.create(function(dap_coroutine)
    local current_buffer_path = vim.api.nvim_buf_get_name(0)
    local build_target = M.find_dotnet_build_target(current_buffer_path)
    local search_root = M.resolve_search_root(build_target)

    M.run_dotnet_debug_build(build_target, function(build_succeeded)
      if not build_succeeded then
        coroutine.resume(dap_coroutine, dap.ABORT)
        return
      end

      local dll_candidates = M.discover_debug_dll_candidates(search_root)
      if #dll_candidates == 0 and search_root ~= vim.fs.normalize(vim.fn.getcwd()) then
        dll_candidates = M.discover_debug_dll_candidates(vim.fn.getcwd())
      end

      if #dll_candidates == 0 then
        local manual_selection = prompt_manual_dll_path(search_root)
        coroutine.resume(dap_coroutine, manual_selection or dap.ABORT)
        return
      end

      local manual_entry_option = "[Enter DLL path manually...]"
      local selection_items = vim.list_extend(vim.deepcopy(dll_candidates), { manual_entry_option })

      vim.ui.select(selection_items, {
        prompt = "Select .NET DLL to debug:",
        format_item = function(item)
          if item == manual_entry_option then
            return item
          end
          return vim.fn.fnamemodify(item, ":.")
        end,
      }, function(choice)
        if not choice then
          coroutine.resume(dap_coroutine, dap.ABORT)
          return
        end

        local selected_dll = choice
        if choice == manual_entry_option then
          selected_dll = prompt_manual_dll_path(search_root)
          if not selected_dll then
            coroutine.resume(dap_coroutine, dap.ABORT)
            return
          end
        end

        coroutine.resume(dap_coroutine, selected_dll)
      end)
    end)
  end)
end

function M.apply_default_working_directory(config)
  if
    (config.type == "netcoredbg" or config.type == "coreclr")
    and config.request == "launch"
    and type(config.program) == "string"
    and (not config.cwd or config.cwd == "")
  then
    local updated_config = vim.deepcopy(config)
    updated_config.cwd = vim.fs.dirname(config.program)
    return updated_config
  end
  return config
end

return M
