# Detect and manage dotnet run, pnpm run dev, and npm run dev processes across Herdr workspaces and panes.
# Usage: dev-servers.ps1 [--badge|--scan|--daemon|--open|--pane|--stop [workspaceId|--all]|--help]

$ErrorActionPreference = "Stop"

$userHomeDirectory = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$cacheDirectory = Join-Path $userHomeDirectory ".cache"
if (-not (Test-Path -LiteralPath $cacheDirectory)) {
  New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
}

$shellsCacheDirectory = Join-Path $cacheDirectory "herdr-shells"
$snapshotFilePath = Join-Path $cacheDirectory "herdr-dev-servers.json"
$badgeFilePath = Join-Path $cacheDirectory "herdr-dev-servers.badge"
$daemonPidFilePath = Join-Path $cacheDirectory "herdr-dev-servers.pid"
$logFilePath = Join-Path $cacheDirectory "herdr-dev-servers.log"

$requestedAction = if ($args.Count -ge 1) { [string]$args[0] } else { "--open" }

function Write-AtomicTextFile {
  param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][string]$Content
  )
  $utf8WithoutByteOrderMark = [System.Text.UTF8Encoding]::new($false)
  $temporaryFilePath = "$TargetPath.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"
  try {
    [System.IO.File]::WriteAllText($temporaryFilePath, $Content, $utf8WithoutByteOrderMark)
    if ([System.IO.File]::Exists($TargetPath)) {
      [System.IO.File]::Replace($temporaryFilePath, $TargetPath, $null)
    } else {
      [System.IO.File]::Move($temporaryFilePath, $TargetPath)
    }
  } catch {
    Remove-Item -LiteralPath $temporaryFilePath -Force -ErrorAction SilentlyContinue
    try {
      [System.IO.File]::WriteAllText($TargetPath, $Content, $utf8WithoutByteOrderMark)
    } catch {}
  }
}

function Write-DevServerLog {
  param(
    [Parameter(Mandatory = $true)][string]$Level,
    [Parameter(Mandatory = $true)][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Message
  )
  try {
    if ([System.IO.File]::Exists($logFilePath)) {
      $logFileInfo = [System.IO.FileInfo]::new($logFilePath)
      if ($logFileInfo.Length -gt 524288) {
        $rotatedLogFilePath = "$logFilePath.1"
        Remove-Item -LiteralPath $rotatedLogFilePath -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $logFilePath -Destination $rotatedLogFilePath -Force -ErrorAction SilentlyContinue
      }
    }
    $timestampIso = [DateTime]::UtcNow.ToString("o")
    $logLine = "[$timestampIso] [$Level] operation=$Operation pid=$PID $Message`n"
    [System.IO.File]::AppendAllText($logFilePath, $logLine, [System.Text.UTF8Encoding]::new($false))
  } catch {}
}

function Test-DevServersDaemonRunning {
  if (-not [System.IO.File]::Exists($daemonPidFilePath)) {
    return $false
  }
  try {
    $rawDaemonPidText = ([System.IO.File]::ReadAllText($daemonPidFilePath)).Trim()
    if ($rawDaemonPidText -eq "starting" -and ([DateTime]::UtcNow - [System.IO.File]::GetLastWriteTimeUtc($daemonPidFilePath)).TotalSeconds -lt 10) {
      return $true
    }
    if ($rawDaemonPidText.StartsWith("win:")) {
      $rawDaemonPidText = $rawDaemonPidText.Substring(4).Trim()
    }
    $parsedDaemonPid = 0
    if ([int]::TryParse($rawDaemonPidText, [ref]$parsedDaemonPid) -and $parsedDaemonPid -gt 0) {
      $daemonProcess = Get-Process -Id $parsedDaemonPid -ErrorAction SilentlyContinue
      if ($null -ne $daemonProcess -and $daemonProcess.ProcessName -in @("powershell", "pwsh")) {
        return $true
      }
    }
  } catch {}
  return $false
}

function Start-DetachedDevServersDaemon {
  Write-AtomicTextFile -TargetPath $daemonPidFilePath -Content "starting`n"
  Write-DevServerLog -Level "INFO" -Operation "daemon_spawn_requested" -Message "spawning detached dev-servers daemon"

  $powerShellExecutable = Join-Path $PSHOME "powershell.exe"
  if (-not (Test-Path -LiteralPath $powerShellExecutable)) {
    $powerShellExecutable = "powershell.exe"
  }

  $isDaemonSpawned = $false
  $spawnedProcessId = 0
  try {
    $escapedPowerShell = $powerShellExecutable.Replace('"', '\"')
    $escapedScriptPath = $PSCommandPath.Replace('"', '\"')
    $daemonCommandLine = "`"$escapedPowerShell`" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$escapedScriptPath`" --daemon"
    $startupInformation = New-CimInstance -ClassName Win32_ProcessStartup -Property @{ ShowWindow = [uint16]0 } -ClientOnly
    $createResult = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
      CommandLine              = $daemonCommandLine
      CurrentDirectory         = $userHomeDirectory
      ProcessStartupInformation = $startupInformation
    } -ErrorAction Stop
    if ($null -ne $createResult -and [uint32]$createResult.ReturnValue -eq 0 -and $createResult.ProcessId) {
      $spawnedProcessId = [int]$createResult.ProcessId
      $isDaemonSpawned = $true
      Write-DevServerLog -Level "INFO" -Operation "daemon_spawn_cim" -Message "spawnedPid=$spawnedProcessId"
    }
  } catch {
    Write-DevServerLog -Level "WARN" -Operation "daemon_spawn_cim" -Message "error=$($_.Exception.Message)"
  }

  if (-not $isDaemonSpawned) {
    try {
      $daemonProcess = Start-Process -FilePath $powerShellExecutable -WorkingDirectory $userHomeDirectory -WindowStyle Hidden -PassThru -ArgumentList @(
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "`"$PSCommandPath`"",
        "--daemon"
      ) -ErrorAction Stop
      if ($null -ne $daemonProcess -and $daemonProcess.Id -gt 0) {
        $spawnedProcessId = [int]$daemonProcess.Id
        $isDaemonSpawned = $true
        Write-DevServerLog -Level "INFO" -Operation "daemon_spawn_startprocess" -Message "spawnedPid=$spawnedProcessId"
      }
    } catch {
      Write-DevServerLog -Level "WARN" -Operation "daemon_spawn_startprocess" -Message "error=$($_.Exception.Message)"
    }
  }

  if ($isDaemonSpawned -and $spawnedProcessId -gt 0) {
    Write-AtomicTextFile -TargetPath $daemonPidFilePath -Content "win:$spawnedProcessId`n"
  } else {
    Remove-Item -LiteralPath $daemonPidFilePath -Force -ErrorAction SilentlyContinue
  }
}

# Fast path for status bar badge polling (<10ms; never blocks on full WMI process scan).
if ($requestedAction -in @("--badge", "badge")) {
  $cachedBadgeText = "DEV: OFF"
  if ([System.IO.File]::Exists($badgeFilePath)) {
    try {
      $rawBadgeText = ([System.IO.File]::ReadAllText($badgeFilePath)).Trim()
      if (-not [string]::IsNullOrWhiteSpace($rawBadgeText)) {
        $cachedBadgeText = $rawBadgeText
      }
    } catch {}
  }

  if (-not (Test-DevServersDaemonRunning)) {
    Start-DetachedDevServersDaemon
  }

  Write-Output $cachedBadgeText
  exit 0
}

function Resolve-HerdrBinary {
  if ($env:HERDR_BIN_PATH -and (Test-Path -LiteralPath $env:HERDR_BIN_PATH)) {
    return $env:HERDR_BIN_PATH
  }
  $herdrExeCommand = Get-Command herdr.exe -ErrorAction SilentlyContinue
  if ($herdrExeCommand -and $herdrExeCommand.Source) {
    return $herdrExeCommand.Source
  }
  $herdrCommand = Get-Command herdr -ErrorAction SilentlyContinue
  if ($herdrCommand -and $herdrCommand.Source) {
    return $herdrCommand.Source
  }
  $standalonePath = Join-Path $userHomeDirectory ".herdr\packages\standalone\current\herdr.exe"
  if (Test-Path -LiteralPath $standalonePath) {
    return $standalonePath
  }
  $userHerdrExecutablePath = Join-Path $userHomeDirectory ".herdr\bin\herdr.exe"
  if (Test-Path -LiteralPath $userHerdrExecutablePath) {
    return $userHerdrExecutablePath
  }
  return $null
}

if ($requestedAction -in @("--pane", "pane")) {
  if (-not (Test-DevServersDaemonRunning)) {
    Start-DetachedDevServersDaemon
  }
  . (Join-Path $PSScriptRoot "dev-servers-tui.ps1")
  Invoke-DevServersOverlayPane
  exit 0
}

function Register-HerdrPluginIfMissing {
  $pluginRootDirectory = Split-Path -Path $PSScriptRoot -Parent
  try {
    $resolvedPluginRoot = (Resolve-Path -LiteralPath $pluginRootDirectory -ErrorAction Stop).ProviderPath
  } catch {
    $resolvedPluginRoot = $pluginRootDirectory
  }
  $manifestFilePath = Join-Path $resolvedPluginRoot "herdr-plugin.toml"
  if (-not (Test-Path -LiteralPath $manifestFilePath)) {
    return
  }

  $pluginId = "dotfiles.dev-servers"
  $registryFilePath = if ($env:APPDATA) {
    Join-Path $env:APPDATA "herdr\plugins.json"
  } elseif ($userHomeDirectory) {
    Join-Path $userHomeDirectory "AppData\Roaming\herdr\plugins.json"
  } else {
    $null
  }

  if (-not [string]::IsNullOrWhiteSpace($registryFilePath) -and (Test-Path -LiteralPath $registryFilePath)) {
    try {
      $rawRegistryJson = [System.IO.File]::ReadAllText($registryFilePath)
      if (-not [string]::IsNullOrWhiteSpace($rawRegistryJson)) {
        $parsedPlugins = @($rawRegistryJson | ConvertFrom-Json)
        $existingEntry = $parsedPlugins | Where-Object { [string]$_.plugin_id -eq $pluginId } | Select-Object -First 1
        if (
          $null -ne $existingEntry -and
          $null -ne $existingEntry.panes -and
          @($existingEntry.panes).Count -gt 0 -and
          [string]$existingEntry.panes[0].command[0] -eq "powershell.exe"
        ) {
          return
        }
      }
    } catch {
      Write-DevServerLog -Level "WARN" -Operation "register_plugin_check" -Message "path=$registryFilePath error=$($_.Exception.Message)"
    }
  }

  $herdrBinaryPath = Resolve-HerdrBinary
  if (-not $herdrBinaryPath) {
    return
  }
  try {
    $linkOutput = (& $herdrBinaryPath plugin link $resolvedPluginRoot 2>&1) -join " | "
    Write-DevServerLog -Level "INFO" -Operation "herdr_plugin_link" -Message "exitCode=$LASTEXITCODE root=$resolvedPluginRoot output=$linkOutput"
  } catch {
    Write-DevServerLog -Level "WARN" -Operation "herdr_plugin_link" -Message "root=$resolvedPluginRoot error=$($_.Exception.Message)"
  }
}

function ConvertTo-NormalizedFilesystemPath {
  param([string]$RawPath)
  if ([string]::IsNullOrWhiteSpace($RawPath)) {
    return ""
  }
  $cleanedPath = $RawPath.Trim().Trim('"', "'")
  if ($cleanedPath.StartsWith("\\?\UNC\", [System.StringComparison]::OrdinalIgnoreCase)) {
    $cleanedPath = "\\" + $cleanedPath.Substring(8)
  } elseif ($cleanedPath.StartsWith("\\?\", [System.StringComparison]::OrdinalIgnoreCase)) {
    $cleanedPath = $cleanedPath.Substring(4)
  }
  $cleanedPath = $cleanedPath.Replace('/', '\').TrimEnd('\')
  return $cleanedPath.ToLowerInvariant()
}

function Get-HerdrSessionMetadata {
  $candidateSessionPaths = @()
  if ($env:APPDATA) {
    $candidateSessionPaths += (Join-Path $env:APPDATA "herdr\session.json")
  }
  $candidateSessionPaths += (Join-Path $userHomeDirectory "AppData\Roaming\herdr\session.json")
  $candidateSessionPaths += (Join-Path $userHomeDirectory ".config\herdr\session.json")

  foreach ($sessionFilePath in $candidateSessionPaths) {
    if (-not (Test-Path -LiteralPath $sessionFilePath)) {
      continue
    }
    try {
      $rawSessionJson = [System.IO.File]::ReadAllText($sessionFilePath)
      if ([string]::IsNullOrWhiteSpace($rawSessionJson)) {
        continue
      }
      return ($rawSessionJson | ConvertFrom-Json)
    } catch {
      Write-DevServerLog -Level "WARN" -Operation "read_session_json" -Message "path=$sessionFilePath error=$($_.Exception.Message)"
    }
  }
  return $null
}

function Get-WorkspaceDisplayLabelById {
  param($SessionMetadata)
  $labelsByWorkspaceId = @{}
  if ($null -eq $SessionMetadata -or $null -eq $SessionMetadata.workspaces) {
    return $labelsByWorkspaceId
  }
  foreach ($workspace in $SessionMetadata.workspaces) {
    $workspaceId = [string]$workspace.id
    if ([string]::IsNullOrWhiteSpace($workspaceId)) {
      continue
    }
    $displayLabel = $workspaceId
    if (-not [string]::IsNullOrWhiteSpace([string]$workspace.custom_name)) {
      if ($null -ne $workspace.worktree_space -and -not [string]::IsNullOrWhiteSpace([string]$workspace.worktree_space.label)) {
        $displayLabel = "$([string]$workspace.worktree_space.label)/$([string]$workspace.custom_name)"
      } else {
        $displayLabel = [string]$workspace.custom_name
      }
    } elseif ($null -ne $workspace.worktree_space) {
      $spaceLabel = [string]$workspace.worktree_space.label
      $checkoutLeaf = if (-not [string]::IsNullOrWhiteSpace([string]$workspace.worktree_space.checkout_path)) {
        Split-Path -Path ([string]$workspace.worktree_space.checkout_path).TrimEnd('\', '/') -Leaf
      } else {
        ""
      }
      if ([bool]$workspace.worktree_space.is_linked_worktree -and -not [string]::IsNullOrWhiteSpace($checkoutLeaf) -and $checkoutLeaf -ne $spaceLabel) {
        $displayLabel = if (-not [string]::IsNullOrWhiteSpace($spaceLabel)) { "$spaceLabel/$checkoutLeaf" } else { $checkoutLeaf }
      } elseif (-not [string]::IsNullOrWhiteSpace($spaceLabel)) {
        $displayLabel = $spaceLabel
      } elseif (-not [string]::IsNullOrWhiteSpace($checkoutLeaf)) {
        $displayLabel = $checkoutLeaf
      }
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$workspace.identity_cwd)) {
      $leafFolder = Split-Path -Path ([string]$workspace.identity_cwd).TrimEnd('\', '/') -Leaf
      if (-not [string]::IsNullOrWhiteSpace($leafFolder)) {
        $displayLabel = $leafFolder
      }
    }
    $labelsByWorkspaceId[$workspaceId] = $displayLabel
  }
  return $labelsByWorkspaceId
}

function Resolve-PublicPaneNumber {
  param(
    $WorkspaceObject,
    [string]$RawPaneId
  )
  if ([string]::IsNullOrWhiteSpace($RawPaneId)) {
    return $null
  }
  $normalizedPaneKey = $RawPaneId.Trim()
  if ($normalizedPaneKey -match '^w[^:]+:p(\d+)$') {
    return [int]$Matches[1]
  }
  if ($normalizedPaneKey.StartsWith("p", [System.StringComparison]::OrdinalIgnoreCase)) {
    $normalizedPaneKey = $normalizedPaneKey.Substring(1)
  }
  if ($null -ne $WorkspaceObject -and $null -ne $WorkspaceObject.public_pane_numbers) {
    $paneNumbersProperty = $WorkspaceObject.public_pane_numbers.PSObject.Properties[$normalizedPaneKey]
    if ($null -ne $paneNumbersProperty -and $null -ne $paneNumbersProperty.Value) {
      return [int]$paneNumbersProperty.Value
    }
  }
  $parsedNumber = 0
  if ([int]::TryParse($normalizedPaneKey, [ref]$parsedNumber)) {
    return $parsedNumber
  }
  return $null
}

function Get-DevServerKindFromProcessInfo {
  param(
    [string]$ProcessName,
    [string]$CommandLine,
    [string]$ExecutablePath = ""
  )
  if ([string]::IsNullOrWhiteSpace($CommandLine) -and [string]::IsNullOrWhiteSpace($ExecutablePath)) {
    return $null
  }
  if ($CommandLine -match '(?i)dev-servers\.(ps1|sh)|herdr-dev-servers') {
    return $null
  }
  if ($CommandLine -match '(?i)(?:^|[\s"''\\/])dotnet(?:\.exe)?["'']?\s+(?:(?:--project|-p|--configuration|-c|--framework|-f|--launch-profile)\s+\S+\s+)*["'']?(?:run|watch)\b["'']?') {
    return "dotnet"
  }
  if (
    ($ExecutablePath -match '(?i)\\bin\\(?:Debug|Release)\\net[^\\/]+\\([^\\/]+)\.exe$' -or
     $CommandLine -match '(?i)\\bin\\(?:Debug|Release)\\net[^\\/]+\\([^\\/"'']+)\.(?:exe|dll)\b') -and
    $ProcessName -notmatch '^(?i)(VBCSCompiler|MSBuild|testhost|csc|vstest)' -and
    $CommandLine -notmatch '(?i)vstest\.console|testhost|\.(?:UnitTests|IntegrationTests|Tests)\.(?:dll|exe)\b' -and
    $ExecutablePath -notmatch '(?i)\.(?:UnitTests|IntegrationTests|Tests)\.exe$'
  ) {
    return "dotnet"
  }
  if ($CommandLine -match '(?i)(?:^|[\s"''\\/])pnpm(?:\.cjs|\.js|\.cmd|\.exe|\.ps1)?["'']?\s+(?:(?:--filter|-F|--dir|-C|--workspace-root)\s+\S+\s+)*(?:["'']?run["'']?\s+)?["'']?dev\b["'']?') {
    return "pnpm"
  }
  if ($CommandLine -match '(?i)(?:^|[\s"''\\/])(?:npm(?:\.cmd|\.exe|\.ps1)?|npm-cli\.js)["'']?\s+(?:(?:--prefix|-C|--workspace|-w)\s+\S+\s+)*["'']?run(?:-script)?["'']?\s+["'']?dev\b["'']?') {
    return "npm"
  }
  if ($ProcessName -match '^(?i)node(\.exe)?$' -and $CommandLine -match '(?i)\\node_modules\\.*\b(vite|next|webpack-dev-server|react-scripts|vue-cli-service|nuxt|astro|ts-node-dev|nodemon)\b') {
    if ($CommandLine -match '(?i)\\\.pnpm\\') {
      return "pnpm"
    }
    return "npm"
  }
  return $null
}

function Get-DescendantProcessIds {
  param(
    [Parameter(Mandatory = $true)][int]$RootProcessId,
    [Parameter(Mandatory = $true)][hashtable]$ChildProcessIdsByParentId
  )
  $descendantProcessIds = [System.Collections.Generic.List[int]]::new()
  $visitedProcessIds = [System.Collections.Generic.HashSet[int]]::new()
  [void]$visitedProcessIds.Add($RootProcessId)

  $processQueue = [System.Collections.Generic.Queue[int]]::new()
  $processQueue.Enqueue($RootProcessId)

  while ($processQueue.Count -gt 0) {
    $currentProcessId = $processQueue.Dequeue()
    if (-not $ChildProcessIdsByParentId.ContainsKey($currentProcessId)) {
      continue
    }
    foreach ($childProcessId in $ChildProcessIdsByParentId[$currentProcessId]) {
      if ($visitedProcessIds.Add([int]$childProcessId)) {
        $descendantProcessIds.Add([int]$childProcessId)
        $processQueue.Enqueue([int]$childProcessId)
      }
    }
  }
  return $descendantProcessIds.ToArray()
}

function Get-CandidateFilesystemPathsFromProcessTree {
  param(
    [Parameter(Mandatory = $true)][int[]]$ProcessIdsInTree,
    [Parameter(Mandatory = $true)][hashtable]$ProcessById
  )
  $candidatePaths = [System.Collections.Generic.List[string]]::new()
  $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

  $addCandidatePath = {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
      return
    }
    $trimmedPath = $PathValue.Trim().Trim('"', "'")
    if ($trimmedPath.Length -lt 3) {
      return
    }
    if ($trimmedPath -match '(?i)\\Windows\\System32|\\Program Files|\\AppData\\|\\nvm\\|\\.nodejs|\\.fnm\\|\\.volta\\|\\.dotnet\\|\\.nuget\\') {
      return
    }
    if ($trimmedPath -match '(?i)^(?<projectRoot>[A-Za-z]:[\\/].+?)[\\/]node_modules(?:[\\/]|$)') {
      $nodeProjectRoot = $Matches['projectRoot']
      if ([System.IO.Directory]::Exists($nodeProjectRoot) -and $seenPaths.Add($nodeProjectRoot)) {
        $candidatePaths.Add($nodeProjectRoot)
      }
      return
    }
    if ($trimmedPath -match '(?i)\\node_modules\\|\\.pnpm\\') {
      return
    }
    if ($trimmedPath -match '(?i)^(?<projectRoot>[A-Za-z]:[\\/].+?)[\\/](?:bin|obj)[\\/](?:Debug|Release)(?:[\\/]|$)') {
      $dotnetProjectRoot = $Matches['projectRoot']
      if ([System.IO.Directory]::Exists($dotnetProjectRoot) -and $seenPaths.Add($dotnetProjectRoot)) {
        $candidatePaths.Add($dotnetProjectRoot)
      }
    }
    if ([System.IO.File]::Exists($trimmedPath)) {
      $parentDirectory = Split-Path -Path $trimmedPath -Parent
      if (-not [string]::IsNullOrWhiteSpace($parentDirectory) -and $seenPaths.Add($parentDirectory)) {
        $candidatePaths.Add($parentDirectory)
      }
      if ($seenPaths.Add($trimmedPath)) {
        $candidatePaths.Add($trimmedPath)
      }
      return
    }
    if ([System.IO.Directory]::Exists($trimmedPath)) {
      if ($seenPaths.Add($trimmedPath)) {
        $candidatePaths.Add($trimmedPath)
      }
    }
  }

  foreach ($processId in $ProcessIdsInTree) {
    if (-not $ProcessById.ContainsKey($processId)) {
      continue
    }
    $processRecord = $ProcessById[$processId]
    $commandLine = [string]$processRecord.CommandLine
    $executablePath = [string]$processRecord.ExecutablePath

    if (-not [string]::IsNullOrWhiteSpace($commandLine)) {
      $flagMatches = [regex]::Matches(
        $commandLine,
        '(?i)(?:--project|--prefix|--dir|-C)\s+(?:"([^"]+)"|''([^'']+)''|(\S+))'
      )
      foreach ($flagMatch in $flagMatches) {
        foreach ($groupIndex in 1..3) {
          if ($flagMatch.Groups[$groupIndex].Success) {
            & $addCandidatePath $flagMatch.Groups[$groupIndex].Value
          }
        }
      }

      $drivePathMatches = [regex]::Matches(
        $commandLine,
        '(?:"([A-Za-z]:[\\/][^"]+)"|''([A-Za-z]:[\\/][^'']+)''|([A-Za-z]:[\\/][^\s"'''']+))'
      )
      foreach ($driveMatch in $drivePathMatches) {
        foreach ($groupIndex in 1..3) {
          if ($driveMatch.Groups[$groupIndex].Success) {
            & $addCandidatePath $driveMatch.Groups[$groupIndex].Value
          }
        }
      }
    }

    if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
      & $addCandidatePath $executablePath
    }
  }

  return $candidatePaths.ToArray()
}

function Find-ShellRegistrationForProcess {
  param(
    [Parameter(Mandatory = $true)][int]$StartProcessId,
    [Parameter(Mandatory = $true)][hashtable]$ProcessById
  )
  if (-not (Test-Path -LiteralPath $shellsCacheDirectory)) {
    return $null
  }
  $currentProcessId = $StartProcessId
  for ($hopIndex = 0; $hopIndex -lt 12; $hopIndex++) {
    if ($currentProcessId -le 0) {
      break
    }
    $shellRegistrationFilePath = Join-Path $shellsCacheDirectory "$currentProcessId.json"
    if ([System.IO.File]::Exists($shellRegistrationFilePath)) {
      try {
        $rawRegistrationJson = [System.IO.File]::ReadAllText($shellRegistrationFilePath)
        $registrationObject = $rawRegistrationJson | ConvertFrom-Json
        if ($null -ne $registrationObject) {
          return $registrationObject
        }
      } catch {}
    }
    if (-not $ProcessById.ContainsKey($currentProcessId)) {
      break
    }
    $parentProcessId = [int]$ProcessById[$currentProcessId].ParentProcessId
    if ($parentProcessId -le 0 -or $parentProcessId -eq $currentProcessId) {
      break
    }
    $currentProcessId = $parentProcessId
  }
  return $null
}

function Resolve-HerdrLocationForServer {
  param(
    $ShellRegistration,
    [string[]]$CandidatePaths,
    $SessionMetadata
  )
  $resolvedWorkspaceId = $null
  $resolvedPaneId = $null
  $resolvedPublicPaneNumber = $null
  $resolvedWorkingDirectory = $null

  if ($null -ne $ShellRegistration) {
    if (-not [string]::IsNullOrWhiteSpace([string]$ShellRegistration.workspace_id)) {
      $resolvedWorkspaceId = [string]$ShellRegistration.workspace_id
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$ShellRegistration.pane_id)) {
      $resolvedPaneId = [string]$ShellRegistration.pane_id
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$ShellRegistration.cwd)) {
      $resolvedWorkingDirectory = [string]$ShellRegistration.cwd
    }
  }

  $allPathsToMatch = [System.Collections.Generic.List[string]]::new()
  if (-not [string]::IsNullOrWhiteSpace($resolvedWorkingDirectory)) {
    $allPathsToMatch.Add($resolvedWorkingDirectory)
  }
  foreach ($candidatePath in $CandidatePaths) {
    if (-not [string]::IsNullOrWhiteSpace($candidatePath)) {
      $allPathsToMatch.Add($candidatePath)
      if ([string]::IsNullOrWhiteSpace($resolvedWorkingDirectory)) {
        $resolvedWorkingDirectory = $candidatePath
      }
    }
  }

  if ($null -ne $SessionMetadata -and $null -ne $SessionMetadata.workspaces) {
    $bestMatchLength = -1
    $bestWorkspaceObject = $null
    $bestMatchingPaneKey = $null

    $workspacesToSearch = if (-not [string]::IsNullOrWhiteSpace($resolvedWorkspaceId)) {
      @($SessionMetadata.workspaces | Where-Object { [string]$_.id -eq $resolvedWorkspaceId })
    } else {
      @($SessionMetadata.workspaces)
    }

    foreach ($rawCandidatePath in $allPathsToMatch) {
      $normalizedCandidatePath = ConvertTo-NormalizedFilesystemPath -RawPath $rawCandidatePath
      if ([string]::IsNullOrWhiteSpace($normalizedCandidatePath)) {
        continue
      }

      foreach ($workspace in $workspacesToSearch) {
        if ($null -ne $workspace.tabs) {
          foreach ($tab in $workspace.tabs) {
            if ($null -eq $tab.panes) {
              continue
            }
            foreach ($paneProperty in $tab.panes.PSObject.Properties) {
              $paneKey = [string]$paneProperty.Name
              $paneWorkingDirectory = [string]$paneProperty.Value.cwd
              $normalizedPanePath = ConvertTo-NormalizedFilesystemPath -RawPath $paneWorkingDirectory
              if ([string]::IsNullOrWhiteSpace($normalizedPanePath)) {
                continue
              }
              $isPrefixMatch = (
                $normalizedCandidatePath -eq $normalizedPanePath -or
                $normalizedCandidatePath.StartsWith("$normalizedPanePath\") -or
                $normalizedPanePath.StartsWith("$normalizedCandidatePath\")
              )
              if ($isPrefixMatch) {
                $effectiveScore = [Math]::Min($normalizedCandidatePath.Length, $normalizedPanePath.Length) + 1000
                if ($effectiveScore -gt $bestMatchLength) {
                  $bestMatchLength = $effectiveScore
                  $bestWorkspaceObject = $workspace
                  $bestMatchingPaneKey = $paneKey
                  if ([string]::IsNullOrWhiteSpace($resolvedWorkingDirectory)) {
                    $resolvedWorkingDirectory = $paneWorkingDirectory
                  }
                }
              }
            }
          }
        }

        $workspacePathsToCompare = @()
        if (-not [string]::IsNullOrWhiteSpace([string]$workspace.identity_cwd)) {
          $workspacePathsToCompare += [string]$workspace.identity_cwd
        }
        if ($null -ne $workspace.worktree_space -and -not [string]::IsNullOrWhiteSpace([string]$workspace.worktree_space.checkout_path)) {
          $workspacePathsToCompare += [string]$workspace.worktree_space.checkout_path
        }

        foreach ($workspaceReferencePath in $workspacePathsToCompare) {
          $normalizedWorkspacePath = ConvertTo-NormalizedFilesystemPath -RawPath $workspaceReferencePath
          if ([string]::IsNullOrWhiteSpace($normalizedWorkspacePath)) {
            continue
          }
          $isWorkspacePrefixMatch = (
            $normalizedCandidatePath -eq $normalizedWorkspacePath -or
            $normalizedCandidatePath.StartsWith("$normalizedWorkspacePath\") -or
            $normalizedWorkspacePath.StartsWith("$normalizedCandidatePath\")
          )
          if ($isWorkspacePrefixMatch) {
            $workspaceScore = [Math]::Min($normalizedCandidatePath.Length, $normalizedWorkspacePath.Length)
            if ($workspaceScore -gt $bestMatchLength) {
              $bestMatchLength = $workspaceScore
              $bestWorkspaceObject = $workspace
            }
          }
        }
      }
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedWorkspaceId)) {
      $explicitWorkspaceObject = $SessionMetadata.workspaces | Where-Object { [string]$_.id -eq $resolvedWorkspaceId } | Select-Object -First 1
      if ($null -ne $explicitWorkspaceObject) {
        $bestWorkspaceObject = $explicitWorkspaceObject
      }
    }

    if ($null -ne $bestWorkspaceObject) {
      if ([string]::IsNullOrWhiteSpace($resolvedWorkspaceId)) {
        $resolvedWorkspaceId = [string]$bestWorkspaceObject.id
      }
      if (-not [string]::IsNullOrWhiteSpace($bestMatchingPaneKey)) {
        $resolvedPublicPaneNumber = Resolve-PublicPaneNumber -WorkspaceObject $bestWorkspaceObject -RawPaneId $bestMatchingPaneKey
      }
      if ($null -eq $resolvedPublicPaneNumber -and -not [string]::IsNullOrWhiteSpace($resolvedPaneId)) {
        $resolvedPublicPaneNumber = Resolve-PublicPaneNumber -WorkspaceObject $bestWorkspaceObject -RawPaneId $resolvedPaneId
      }
      if ([string]::IsNullOrWhiteSpace($resolvedPaneId) -and -not [string]::IsNullOrWhiteSpace($bestMatchingPaneKey)) {
        if ($null -ne $resolvedPublicPaneNumber -and -not [string]::IsNullOrWhiteSpace($resolvedWorkspaceId)) {
          $resolvedPaneId = "${resolvedWorkspaceId}:p${resolvedPublicPaneNumber}"
        } elseif (-not [string]::IsNullOrWhiteSpace($resolvedWorkspaceId)) {
          $resolvedPaneId = "${resolvedWorkspaceId}:p${bestMatchingPaneKey}"
        } else {
          $resolvedPaneId = "p$bestMatchingPaneKey"
        }
      }
    }
  }

  if ($null -eq $resolvedPublicPaneNumber -and -not [string]::IsNullOrWhiteSpace($resolvedPaneId)) {
    $resolvedPublicPaneNumber = Resolve-PublicPaneNumber -WorkspaceObject $null -RawPaneId $resolvedPaneId
  }

  return [PSCustomObject]@{
    workspaceId      = $resolvedWorkspaceId
    paneId           = $resolvedPaneId
    publicPaneNumber = $resolvedPublicPaneNumber
    cwd              = $resolvedWorkingDirectory
  }
}

function Add-ProcessListeningPort {
  param(
    [AllowEmptyCollection()][hashtable]$PortsByProcessId,
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][int]$Port
  )
  if ($null -eq $PortsByProcessId -or $ProcessId -le 0 -or $Port -le 0) {
    return
  }
  if (-not $PortsByProcessId.ContainsKey($ProcessId)) {
    $PortsByProcessId[$ProcessId] = [System.Collections.Generic.HashSet[int]]::new()
  }
  [void]$PortsByProcessId[$ProcessId].Add($Port)
}

function Get-ListeningTcpPortsByProcessId {
  $portsByProcessId = @{}
  try {
    $netstatExecutable = if ($env:SystemRoot) { Join-Path $env:SystemRoot "System32\netstat.exe" } else { "netstat.exe" }
    if (-not (Test-Path -LiteralPath $netstatExecutable)) {
      $netstatExecutable = "netstat.exe"
    }
    $netstatLines = & $netstatExecutable -ano
    foreach ($line in $netstatLines) {
      if ($line -match '(?i)^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTEN\S*\s+(\d+)\s*$') {
        $localPort = [int]$Matches[1]
        $owningProcessId = [int]$Matches[2]
        Add-ProcessListeningPort -PortsByProcessId $portsByProcessId -ProcessId $owningProcessId -Port $localPort
      }
    }
  } catch {
    Write-DevServerLog -Level "WARN" -Operation "get_listening_ports_netstat" -Message "error=$($_.Exception.Message)"
  }
  if ($portsByProcessId.Count -eq 0) {
    try {
      $listeningConnections = Get-NetTCPConnection -State Listen -ErrorAction Stop
      foreach ($connection in $listeningConnections) {
        Add-ProcessListeningPort -PortsByProcessId $portsByProcessId -ProcessId ([int]$connection.OwningProcess) -Port ([int]$connection.LocalPort)
      }
    } catch {
      Write-DevServerLog -Level "WARN" -Operation "get_listening_ports_cim" -Message "error=$($_.Exception.Message)"
    }
  }
  return $portsByProcessId
}

$script:ExplicitPortRegex = [regex]::new(
  '(?i)(?:--urls\s+\S*?https?://[^/\s"'''';]+:(\d+)|https?://[^/\s"'''';]+:(\d+)|--port(?:=|\s+)(\d+))',
  [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

function Get-DetectedDevServersSnapshot {
  $processById = @{}
  $childProcessIdsByParentId = @{}
  $matchedKindByProcessId = @{}

  $allProcesses = @(Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,Name,CommandLine,ExecutablePath -ErrorAction SilentlyContinue)
  foreach ($processRecord in $allProcesses) {
    $processId = [int]$processRecord.ProcessId
    if ($processId -le 0 -or $processId -eq $PID) {
      continue
    }
    $processById[$processId] = $processRecord
    $parentProcessId = [int]$processRecord.ParentProcessId
    if ($parentProcessId -gt 0) {
      if (-not $childProcessIdsByParentId.ContainsKey($parentProcessId)) {
        $childProcessIdsByParentId[$parentProcessId] = [System.Collections.Generic.List[int]]::new()
      }
      $childProcessIdsByParentId[$parentProcessId].Add($processId)
    }

    $detectedKind = Get-DevServerKindFromProcessInfo `
      -ProcessName ([string]$processRecord.Name) `
      -CommandLine ([string]$processRecord.CommandLine) `
      -ExecutablePath ([string]$processRecord.ExecutablePath)
    if ($null -ne $detectedKind) {
      $matchedKindByProcessId[$processId] = $detectedKind
    }
  }

  # Deduplicate nested wrapper processes: keep only root processes that have no matched ancestor.
  $rootProcessIds = [System.Collections.Generic.List[int]]::new()
  foreach ($candidateProcessId in $matchedKindByProcessId.Keys) {
    $hasMatchedAncestor = $false
    $currentParentId = [int]$processById[$candidateProcessId].ParentProcessId
    for ($hop = 0; $hop -lt 16; $hop++) {
      if ($currentParentId -le 0 -or -not $processById.ContainsKey($currentParentId)) {
        break
      }
      if ($matchedKindByProcessId.ContainsKey($currentParentId)) {
        $hasMatchedAncestor = $true
        break
      }
      $nextParentId = [int]$processById[$currentParentId].ParentProcessId
      if ($nextParentId -eq $currentParentId) {
        break
      }
      $currentParentId = $nextParentId
    }
    if (-not $hasMatchedAncestor) {
      $rootProcessIds.Add([int]$candidateProcessId)
    }
  }

  $listeningPortsByProcessId = Get-ListeningTcpPortsByProcessId
  $sessionMetadata = Get-HerdrSessionMetadata
  $workspaceDisplayLabelById = Get-WorkspaceDisplayLabelById -SessionMetadata $sessionMetadata
  $detectedServers = [System.Collections.Generic.List[object]]::new()

  $descendantsByRootPid = @{}
  $allClaimedTreeProcessIds = [System.Collections.Generic.HashSet[int]]::new()
  foreach ($rootProcessId in ($rootProcessIds | Sort-Object)) {
    $descendantProcessIds = @(Get-DescendantProcessIds -RootProcessId $rootProcessId -ChildProcessIdsByParentId $childProcessIdsByParentId)
    $descendantsByRootPid[$rootProcessId] = $descendantProcessIds
    [void]$allClaimedTreeProcessIds.Add([int]$rootProcessId)
    foreach ($descendantProcessId in $descendantProcessIds) {
      [void]$allClaimedTreeProcessIds.Add([int]$descendantProcessId)
    }
  }

  foreach ($rootProcessId in ($rootProcessIds | Sort-Object)) {
    $rootProcessRecord = $processById[$rootProcessId]
    $serverKind = $matchedKindByProcessId[$rootProcessId]
    $descendantProcessIds = @($descendantsByRootPid[$rootProcessId])
    $allTreeProcessIds = @($rootProcessId) + $descendantProcessIds

    $listeningPortsSet = [System.Collections.Generic.HashSet[int]]::new()
    $listenerProcessIdsSet = [System.Collections.Generic.HashSet[int]]::new()

    foreach ($treeProcessId in $allTreeProcessIds) {
      if ($listeningPortsByProcessId.ContainsKey($treeProcessId)) {
        [void]$listenerProcessIdsSet.Add([int]$treeProcessId)
        foreach ($listeningPort in $listeningPortsByProcessId[$treeProcessId]) {
          [void]$listeningPortsSet.Add([int]$listeningPort)
        }
      }
      if ($processById.ContainsKey($treeProcessId)) {
        $treeCommandLine = [string]$processById[$treeProcessId].CommandLine
        if (-not [string]::IsNullOrWhiteSpace($treeCommandLine)) {
          $explicitPortMatches = $script:ExplicitPortRegex.Matches($treeCommandLine)
          foreach ($portMatch in $explicitPortMatches) {
            foreach ($captureGroupIndex in 1..3) {
              if ($portMatch.Groups[$captureGroupIndex].Success) {
                $parsedExplicitPort = [int]$portMatch.Groups[$captureGroupIndex].Value
                if ($parsedExplicitPort -gt 0) {
                  [void]$listeningPortsSet.Add($parsedExplicitPort)
                }
              }
            }
          }
        }
      }
    }

    $candidateFilesystemPaths = @(Get-CandidateFilesystemPathsFromProcessTree -ProcessIdsInTree $allTreeProcessIds -ProcessById $processById)
    $shellRegistration = Find-ShellRegistrationForProcess -StartProcessId $rootProcessId -ProcessById $processById
    $locationInfo = Resolve-HerdrLocationForServer -ShellRegistration $shellRegistration -CandidatePaths $candidateFilesystemPaths -SessionMetadata $sessionMetadata

    $projectPath = if ($candidateFilesystemPaths.Count -gt 0) {
      $candidateFilesystemPaths[0]
    } else {
      $locationInfo.cwd
    }

    if (-not [string]::IsNullOrWhiteSpace($projectPath)) {
      foreach ($candidateListenerProcessId in $listeningPortsByProcessId.Keys) {
        if ($allClaimedTreeProcessIds.Contains([int]$candidateListenerProcessId)) {
          continue
        }
        $candidateListenerProcess = $processById[[int]$candidateListenerProcessId]
        if ($null -eq $candidateListenerProcess) {
          continue
        }
        if ($serverKind -in @("pnpm", "npm") -and $candidateListenerProcess.Name -notmatch '^(?i)node') {
          continue
        }
        if ($serverKind -eq "dotnet" -and $candidateListenerProcess.Name -match '^(?i)node') {
          continue
        }
        $candidateListenerCommandLine = [string]$candidateListenerProcess.CommandLine
        $candidateListenerExecutablePath = [string]$candidateListenerProcess.ExecutablePath
        $matchesProjectPath = (
          (-not [string]::IsNullOrWhiteSpace($candidateListenerCommandLine) -and $candidateListenerCommandLine.IndexOf($projectPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
          (-not [string]::IsNullOrWhiteSpace($candidateListenerExecutablePath) -and $candidateListenerExecutablePath.IndexOf($projectPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
        )
        if ($matchesProjectPath) {
          [void]$listenerProcessIdsSet.Add([int]$candidateListenerProcessId)
          foreach ($listeningPort in $listeningPortsByProcessId[$candidateListenerProcessId]) {
            [void]$listeningPortsSet.Add([int]$listeningPort)
          }
        }
      }
    }

    $sortedPorts = @($listeningPortsSet | Sort-Object)
    $sortedListenerProcessIds = @($listenerProcessIdsSet | Sort-Object)

    $commandText = ([string]$rootProcessRecord.CommandLine).Trim()
    $resolvedWorkspaceIdString = [string]$locationInfo.workspaceId
    $workspaceDisplayLabel = if (-not [string]::IsNullOrWhiteSpace($resolvedWorkspaceIdString) -and $workspaceDisplayLabelById.ContainsKey($resolvedWorkspaceIdString)) {
      [string]$workspaceDisplayLabelById[$resolvedWorkspaceIdString]
    } elseif (-not [string]::IsNullOrWhiteSpace($resolvedWorkspaceIdString)) {
      $resolvedWorkspaceIdString
    } else {
      "-"
    }
    $detectedServers.Add([PSCustomObject]@{
      id               = "$serverKind-$rootProcessId"
      rootPid          = [int]$rootProcessId
      childPids        = @($descendantProcessIds)
      listenerPids     = @($sortedListenerProcessIds)
      kind             = [string]$serverKind
      command          = $commandText
      projectPath      = $projectPath
      cwd              = $locationInfo.cwd
      ports            = @($sortedPorts)
      workspaceId      = $locationInfo.workspaceId
      workspaceLabel   = $workspaceDisplayLabel
      paneId           = $locationInfo.paneId
      publicPaneNumber = $locationInfo.publicPaneNumber
    })
  }

  return [PSCustomObject]@{
    updatedAtUnixMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    servers         = @($detectedServers.ToArray())
  }
}

function Format-DevServersBadgeText {
  param($Snapshot)
  $serversList = if ($null -ne $Snapshot -and $null -ne $Snapshot.servers) { @($Snapshot.servers) } else { @() }
  $serverCount = $serversList.Count
  if ($serverCount -gt 0) {
    return "DEV: ON"
  }
  return "DEV: OFF"
}

function Write-SnapshotAndBadgeFiles {
  param($Snapshot)
  $snapshotJson = $Snapshot | ConvertTo-Json -Depth 6
  $badgeText = Format-DevServersBadgeText -Snapshot $Snapshot
  Write-AtomicTextFile -TargetPath $snapshotFilePath -Content "$snapshotJson`n"
  Write-AtomicTextFile -TargetPath $badgeFilePath -Content "$badgeText`n"
  return $badgeText
}

function Report-WorkspaceMetadataAndNotifications {
  param(
    $CurrentSnapshot,
    [hashtable]$PreviousWorkspaceSummaries,
    [hashtable]$PreviousServerPortsById
  )
  $herdrBinaryPath = Resolve-HerdrBinary
  if (-not $herdrBinaryPath) {
    return
  }

  $serversByWorkspaceId = @{}
  foreach ($server in @($CurrentSnapshot.servers)) {
    $workspaceId = [string]$server.workspaceId
    if (-not [string]::IsNullOrWhiteSpace($workspaceId)) {
      if (-not $serversByWorkspaceId.ContainsKey($workspaceId)) {
        $serversByWorkspaceId[$workspaceId] = [System.Collections.Generic.List[object]]::new()
      }
      $serversByWorkspaceId[$workspaceId].Add($server)
    }

    $serverId = [string]$server.id
    $currentPortsText = (@($server.ports) -join ",")
    $previousPortsText = if ($PreviousServerPortsById.ContainsKey($serverId)) { $PreviousServerPortsById[$serverId] } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($currentPortsText) -and $currentPortsText -ne $previousPortsText) {
      $formattedPorts = (@($server.ports | ForEach-Object { ":$_" }) -join " ")
      $workspaceSuffix = if (-not [string]::IsNullOrWhiteSpace($workspaceId)) { " in $workspaceId" } else { "" }
      try {
        & $herdrBinaryPath notification show "Dev Server Ready ($($server.kind))" --body "Listening on $formattedPorts$workspaceSuffix (PID $($server.rootPid))" --position top-right --sound none *>$null
      } catch {}
      Write-DevServerLog -Level "INFO" -Operation "server_port_bound" -Message "id=$serverId workspace=$workspaceId ports=$formattedPorts"
    }
    $PreviousServerPortsById[$serverId] = $currentPortsText
  }

  foreach ($workspaceId in $serversByWorkspaceId.Keys) {
    $workspaceServers = $serversByWorkspaceId[$workspaceId]
    $summaryParts = [System.Collections.Generic.List[string]]::new()
    foreach ($workspaceServer in $workspaceServers) {
      if (@($workspaceServer.ports).Count -gt 0) {
        $portLabels = (@($workspaceServer.ports | Select-Object -First 2 | ForEach-Object { ":$_" }) -join "")
        $summaryParts.Add("$($workspaceServer.kind)$portLabels")
      } else {
        $summaryParts.Add("$($workspaceServer.kind)")
      }
    }
    $summaryValue = $summaryParts -join " "
    $previousValue = if ($PreviousWorkspaceSummaries.ContainsKey($workspaceId)) { $PreviousWorkspaceSummaries[$workspaceId] } else { "" }
    if ($summaryValue -ne $previousValue) {
      try {
        & $herdrBinaryPath workspace report-metadata $workspaceId --source dev-servers --token "dev_servers=$summaryValue" *>$null
      } catch {}
      $PreviousWorkspaceSummaries[$workspaceId] = $summaryValue
    }
  }

  $clearedWorkspaceIds = @($PreviousWorkspaceSummaries.Keys | Where-Object { -not $serversByWorkspaceId.ContainsKey($_) })
  foreach ($clearedWorkspaceId in $clearedWorkspaceIds) {
    try {
      & $herdrBinaryPath workspace report-metadata $clearedWorkspaceId --source dev-servers --clear-token dev_servers *>$null
    } catch {}
    $PreviousWorkspaceSummaries.Remove($clearedWorkspaceId)
  }
}

function Test-DaemonPidOwnedByCurrentProcess {
  if (-not [System.IO.File]::Exists($daemonPidFilePath)) {
    return $false
  }
  try {
    $recordedPidToken = ([System.IO.File]::ReadAllText($daemonPidFilePath)).Trim()
    return ($recordedPidToken -eq "win:$PID" -or $recordedPidToken -eq "$PID")
  } catch {
    return $false
  }
}

function Invoke-DevServersDaemon {
  Write-AtomicTextFile -TargetPath $daemonPidFilePath -Content "win:$PID`n"
  Write-DevServerLog -Level "INFO" -Operation "daemon_start" -Message "started dev-servers daemon"

  $daemonScriptLastWriteUtc = [System.IO.File]::GetLastWriteTimeUtc($PSCommandPath)
  $previousWorkspaceSummaries = @{}
  $previousServerPortsById = @{}
  $hasObservedHerdrProcess = $null -ne (Get-Process -Name "herdr*" -ErrorAction SilentlyContinue)
  $isFirstPoll = $true

  try {
    while (Test-DaemonPidOwnedByCurrentProcess) {
      if ([System.IO.File]::GetLastWriteTimeUtc($PSCommandPath) -ne $daemonScriptLastWriteUtc) {
        Write-DevServerLog -Level "INFO" -Operation "daemon_reload_script_changed" -Message "reloading daemon after script modification"
        break
      }

      $isHerdrCurrentlyRunning = $null -ne (Get-Process -Name "herdr*" -ErrorAction SilentlyContinue)
      if ($isHerdrCurrentlyRunning) {
        $hasObservedHerdrProcess = $true
      } elseif ($hasObservedHerdrProcess) {
        break
      }

      try {
        $currentSnapshot = Get-DetectedDevServersSnapshot
        if ($isFirstPoll) {
          Write-DevServerLog -Level "INFO" -Operation "daemon_first_poll" -Message "detectedCount=$(@($currentSnapshot.servers).Count)"
          $isFirstPoll = $false
        }
        [void](Write-SnapshotAndBadgeFiles -Snapshot $currentSnapshot)
        Report-WorkspaceMetadataAndNotifications `
          -CurrentSnapshot $currentSnapshot `
          -PreviousWorkspaceSummaries $previousWorkspaceSummaries `
          -PreviousServerPortsById $previousServerPortsById
      } catch {
        Write-DevServerLog -Level "ERROR" -Operation "daemon_poll" -Message "error=$($_.Exception.Message)"
      }

      for ($sleepSliceIndex = 0; $sleepSliceIndex -lt 10; $sleepSliceIndex++) {
        if (-not [System.IO.File]::Exists($daemonPidFilePath)) {
          break
        }
        Start-Sleep -Milliseconds 200
      }
    }
  } finally {
    try {
      if (Test-DaemonPidOwnedByCurrentProcess) {
        Remove-Item -LiteralPath $daemonPidFilePath -Force -ErrorAction SilentlyContinue
        Write-AtomicTextFile -TargetPath $badgeFilePath -Content "DEV: OFF`n"
      }
    } catch {
      Write-DevServerLog -Level "WARN" -Operation "daemon_cleanup" -Message "error=$($_.Exception.Message)"
    }
    Write-DevServerLog -Level "INFO" -Operation "daemon_stop" -Message "stopped dev-servers daemon"
  }
}

function Stop-DevServerProcessTree {
  param([Parameter(Mandatory = $true)]$ServerRecord)
  $rootProcessId = [int]$ServerRecord.rootPid
  if ($rootProcessId -le 0) {
    return $false
  }
  Write-DevServerLog -Level "INFO" -Operation "stop_server" -Message "id=$($ServerRecord.id) rootPid=$rootProcessId workspace=$($ServerRecord.workspaceId)"
  try {
    & taskkill.exe /T /F /PID $rootProcessId *>$null
  } catch {}
  foreach ($childProcessId in @($ServerRecord.childPids)) {
    Stop-Process -Id ([int]$childProcessId) -Force -ErrorAction SilentlyContinue
  }
  Stop-Process -Id $rootProcessId -Force -ErrorAction SilentlyContinue
  return $true
}

function Stop-WorkspaceDevServers {
  param([string]$TargetWorkspaceSelector)
  $snapshot = Get-DetectedDevServersSnapshot
  $allServers = @($snapshot.servers)
  if ($allServers.Count -eq 0) {
    [void](Write-SnapshotAndBadgeFiles -Snapshot $snapshot)
    Write-Output "No active dev servers detected."
    return
  }

  $effectiveWorkspaceId = $TargetWorkspaceSelector
  if ([string]::IsNullOrWhiteSpace($effectiveWorkspaceId) -and -not [string]::IsNullOrWhiteSpace($env:HERDR_WORKSPACE_ID)) {
    $effectiveWorkspaceId = $env:HERDR_WORKSPACE_ID
  }

  $serversToStop = if ([string]::IsNullOrWhiteSpace($effectiveWorkspaceId) -or $effectiveWorkspaceId -eq "--all") {
    $allServers
  } else {
    @($allServers | Where-Object { [string]$_.workspaceId -eq $effectiveWorkspaceId })
  }

  if ($serversToStop.Count -eq 0) {
    Write-DevServerLog -Level "INFO" -Operation "stop_workspace_servers" -Message "workspace=$effectiveWorkspaceId stopped=0"
    Write-Output "STOPPED:0"
    return
  }

  $stoppedCount = 0
  foreach ($serverRecord in $serversToStop) {
    if (Stop-DevServerProcessTree -ServerRecord $serverRecord) {
      $stoppedCount++
    }
  }

  Start-Sleep -Milliseconds 300
  $updatedSnapshot = Get-DetectedDevServersSnapshot
  [void](Write-SnapshotAndBadgeFiles -Snapshot $updatedSnapshot)

  $herdrBinaryPath = Resolve-HerdrBinary
  if ($herdrBinaryPath) {
    try {
      & $herdrBinaryPath notification show "Dev Servers Stopped" --body "Stopped $stoppedCount dev server process tree(s)" --position top-right --sound none *>$null
    } catch {}
  }
  Write-Output "Stopped $stoppedCount dev server(s)."
}

$tuiModulePath = Join-Path $PSScriptRoot "dev-servers-tui.ps1"

switch ($requestedAction) {
  { $_ -in @("--scan", "scan") } {
    $snapshot = Get-DetectedDevServersSnapshot
    [void](Write-SnapshotAndBadgeFiles -Snapshot $snapshot)
    Write-Output ($snapshot | ConvertTo-Json -Depth 6)
  }
  { $_ -in @("--daemon", "daemon") } {
    Invoke-DevServersDaemon
  }
  { $_ -in @("--open", "open") } {
    if (Test-Path -LiteralPath $tuiModulePath) {
      . $tuiModulePath
    }
    Show-DevServersBoard
  }
  { $_ -in @("--pane", "pane") } {
    if (Test-Path -LiteralPath $tuiModulePath) {
      . $tuiModulePath
    }
    Invoke-DevServersOverlayPane
  }
  { $_ -in @("--stop", "stop") } {
    $workspaceSelector = if ($args.Count -ge 2) { [string]$args[1] } else { "" }
    Stop-WorkspaceDevServers -TargetWorkspaceSelector $workspaceSelector
  }
  { $_ -in @("--help", "-h", "help") } {
    Write-Output "usage: dev-servers.ps1 [--badge|--scan|--daemon|--open|--pane|--stop [workspaceId|--all]]"
  }
  default {
    [Console]::Error.WriteLine("usage: dev-servers.ps1 [--badge|--scan|--daemon|--open|--pane|--stop [workspaceId|--all]]")
    exit 1
  }
}
