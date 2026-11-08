# TUI overlay board for the dotfiles.dev-servers Herdr plugin (PowerShell).
# Dot-sourced by dev-servers.ps1.

function Resolve-ServerWorkspaceDisplayLabel {
  param($ServerRecord)
  if ($null -eq $ServerRecord) {
    return "-"
  }
  if (-not [string]::IsNullOrWhiteSpace([string]$ServerRecord.workspaceLabel)) {
    return [string]$ServerRecord.workspaceLabel
  }
  if (-not [string]::IsNullOrWhiteSpace([string]$ServerRecord.workspaceId)) {
    return [string]$ServerRecord.workspaceId
  }
  return "-"
}

function Send-DevServersStatusNotification {
  param(
    [string]$HerdrBinaryPath,
    [string]$FailureReason = ""
  )
  $snapshot = Get-DetectedDevServersSnapshot
  $badgeText = Write-SnapshotAndBadgeFiles -Snapshot $snapshot
  $serversList = @($snapshot.servers)
  if (-not $HerdrBinaryPath) {
    return
  }
  $notificationBody = if ($serversList.Count -gt 0) {
    ($serversList | ForEach-Object {
      $portsLabel = if (@($_.ports).Count -gt 0) { (@($_.ports | ForEach-Object { ":$_" }) -join "") } else { "" }
      $resolvedWorkspaceLabel = Resolve-ServerWorkspaceDisplayLabel -ServerRecord $_
      $workspaceLabelSuffix = if ($resolvedWorkspaceLabel -ne "-") { " [$resolvedWorkspaceLabel]" } else { "" }
      "$($_.kind)$portsLabel$workspaceLabelSuffix"
    }) -join ", "
  } else {
    "No active dotnet/pnpm/npm dev servers detected"
  }
  if (-not [string]::IsNullOrWhiteSpace($FailureReason)) {
    $notificationBody = "$notificationBody (overlay error: $FailureReason)"
  }
  try {
    & $HerdrBinaryPath notification show "Dev Servers ($badgeText)" --body $notificationBody --position top-right --sound none *>$null
  } catch {
    Write-DevServerLog -Level "WARN" -Operation "send_status_notification" -Message "error=$($_.Exception.Message)"
  }
}

function Show-DevServersBoard {
  Register-HerdrPluginIfMissing
  $herdrBinaryPath = Resolve-HerdrBinary
  $overlayFailureReason = ""
  if ($herdrBinaryPath) {
    try {
      $openOutput = & $herdrBinaryPath plugin pane open --plugin dotfiles.dev-servers --entrypoint board --placement overlay 2>&1
      if ($LASTEXITCODE -eq 0) {
        Write-DevServerLog -Level "INFO" -Operation "open_overlay" -Message "status=ok"
        return
      }
      $overlayFailureReason = ($openOutput -join ' ').Trim()
      Write-DevServerLog -Level "WARN" -Operation "open_overlay" -Message "exitCode=$LASTEXITCODE output=$overlayFailureReason"
    } catch {
      $overlayFailureReason = $_.Exception.Message
      Write-DevServerLog -Level "WARN" -Operation "open_overlay" -Message "error=$overlayFailureReason"
    }
  }

  $isInteractiveConsole = [Environment]::UserInteractive -and
    (-not [Console]::IsInputRedirected) -and
    (-not ([Environment]::CommandLine -match '(?i)-NonInteractive|-WindowStyle\s+Hidden'))

  if (-not $isInteractiveConsole) {
    Send-DevServersStatusNotification -HerdrBinaryPath $herdrBinaryPath -FailureReason $overlayFailureReason
    return
  }

  Invoke-DevServersOverlayPane
}

function Get-SnapshotLastWriteTimeUtc {
  return [System.IO.File]::GetLastWriteTimeUtc($snapshotFilePath)
}

function Read-CachedDevServersSnapshot {
  if ([System.IO.File]::Exists($snapshotFilePath)) {
    try {
      $rawJson = [System.IO.File]::ReadAllText($snapshotFilePath)
      if (-not [string]::IsNullOrWhiteSpace($rawJson)) {
        return ($rawJson | ConvertFrom-Json)
      }
    } catch {
      Write-DevServerLog -Level "WARN" -Operation "read_cached_snapshot" -Message "path=$snapshotFilePath error=$($_.Exception.Message)"
    }
  }
  return [PSCustomObject]@{ updatedAtUnixMs = 0; servers = @() }
}

function Format-DevServersBoardFrame {
  param(
    [array]$ServersList,
    [int]$SelectedIndex,
    [string]$StatusBannerMessage
  )
  $escapeCharacter = [char]27
  $clearToEndOfLine = "$escapeCharacter[K"
  $accentCyan = "$escapeCharacter[38;2;125;207;255m"
  $accentBlue = "$escapeCharacter[38;2;122;162;247m"
  $accentGreen = "$escapeCharacter[38;2;158;206;106m"
  $accentYellow = "$escapeCharacter[38;2;224;175;104m"
  $accentMagenta = "$escapeCharacter[38;2;187;154;247m"
  $mutedGray = "$escapeCharacter[38;2;86;95;137m"
  $selectedRowStyle = "$escapeCharacter[48;2;41;46;66m$escapeCharacter[38;2;192;202;245m"
  $resetStyle = "$escapeCharacter[0m"

  $frameBuilder = [System.Text.StringBuilder]::new(2048)
  [void]$frameBuilder.Append("$escapeCharacter[H")
  [void]$frameBuilder.AppendLine("${accentCyan}================================================================================${resetStyle}${clearToEndOfLine}")
  [void]$frameBuilder.AppendLine("  ${accentBlue}HERDR DEV SERVERS${resetStyle}  ${mutedGray}|  Active: $($ServersList.Count)  |  Updated: $([DateTime]::Now.ToString('HH:mm:ss'))${resetStyle}${clearToEndOfLine}")
  [void]$frameBuilder.AppendLine("${accentCyan}================================================================================${resetStyle}${clearToEndOfLine}")
  [void]$frameBuilder.AppendLine($clearToEndOfLine)

  if ($ServersList.Count -eq 0) {
    [void]$frameBuilder.AppendLine("  ${mutedGray}No active dotnet run, pnpm run dev, or npm run dev servers detected.${resetStyle}${clearToEndOfLine}")
    [void]$frameBuilder.AppendLine($clearToEndOfLine)
  } else {
    $headerLine = ("  {0,-3} {1,-26} {2,-6} {3,-7} {4,-8} {5,-12} {6}" -f "#", "Workspace", "Pane", "Type", "Root PID", "Ports", "Project / Command")
    [void]$frameBuilder.AppendLine("${accentMagenta}${headerLine}${resetStyle}${clearToEndOfLine}")
    [void]$frameBuilder.AppendLine("  ${mutedGray}------------------------------------------------------------------------------${resetStyle}${clearToEndOfLine}")

    for ($rowIndex = 0; $rowIndex -lt $ServersList.Count; $rowIndex++) {
      $server = $ServersList[$rowIndex]
      $workspaceLabel = Resolve-ServerWorkspaceDisplayLabel -ServerRecord $server
      if ($workspaceLabel.Length -gt 26) {
        $workspaceLabel = $workspaceLabel.Substring(0, 25) + "~"
      }

      $paneDisplay = if ($null -ne $server.publicPaneNumber) {
        "#$($server.publicPaneNumber)"
      } elseif (-not [string]::IsNullOrWhiteSpace([string]$server.paneId)) {
        [string]$server.paneId
      } else {
        "-"
      }

      $portsDisplay = if (@($server.ports).Count -gt 0) {
        (@($server.ports | ForEach-Object { ":$_" }) -join " ")
      } else {
        "-"
      }
      if ($portsDisplay.Length -gt 12) {
        $portsDisplay = $portsDisplay.Substring(0, 11) + "~"
      }

      $projectOrCommandDisplay = if (-not [string]::IsNullOrWhiteSpace([string]$server.projectPath)) {
        Split-Path -Path ([string]$server.projectPath).TrimEnd('\', '/') -Leaf
      } else {
        [string]$server.command
      }
      if ($projectOrCommandDisplay.Length -gt 24) {
        $projectOrCommandDisplay = $projectOrCommandDisplay.Substring(0, 23) + "~"
      }

      $selectorGlyph = if ($rowIndex -eq $SelectedIndex) { ">" } else { " " }
      $formattedRow = ("  {0,-3} {1,-26} {2,-6} {3,-7} {4,-8} {5,-12} {6}" -f "$selectorGlyph$($rowIndex + 1)", $workspaceLabel, $paneDisplay, $server.kind, $server.rootPid, $portsDisplay, $projectOrCommandDisplay)

      if ($rowIndex -eq $SelectedIndex) {
        [void]$frameBuilder.AppendLine("${selectedRowStyle}${formattedRow}${resetStyle}${clearToEndOfLine}")
      } else {
        [void]$frameBuilder.AppendLine("${accentGreen}${formattedRow}${resetStyle}${clearToEndOfLine}")
      }
    }
    [void]$frameBuilder.AppendLine($clearToEndOfLine)
  }

  if (-not [string]::IsNullOrWhiteSpace($StatusBannerMessage)) {
    [void]$frameBuilder.AppendLine("  ${accentYellow}${StatusBannerMessage}${resetStyle}${clearToEndOfLine}")
    [void]$frameBuilder.AppendLine($clearToEndOfLine)
  }

  [void]$frameBuilder.Append("  ${accentCyan}[Up/Down]${resetStyle} Select  ${accentCyan}[Enter]${resetStyle} Focus Workspace  ${accentCyan}[k/x]${resetStyle} Kill Server Tree  ${accentCyan}[r]${resetStyle} Refresh  ${accentCyan}[q/Esc]${resetStyle} Close${clearToEndOfLine}$escapeCharacter[J")
  return $frameBuilder.ToString()
}

function Read-OverlayCommandKey {
  param([DateTime]$LastSnapshotWriteUtc)
  try {
    if (-not [Console]::KeyAvailable) {
      for ($waitTick = 0; $waitTick -lt 50; $waitTick++) {
        if ([Console]::KeyAvailable) {
          break
        }
        if (($waitTick % 5 -eq 4) -and ((Get-SnapshotLastWriteTimeUtc) -ne $LastSnapshotWriteUtc)) {
          break
        }
        Start-Sleep -Milliseconds 40
      }
      if (-not [Console]::KeyAvailable) {
        return $null
      }
    }

    $pressedKey = [Console]::ReadKey($true)
    return [string]$pressedKey.Key
  } catch {
    $lineInput = [Console]::In.ReadLine()
    if ($null -eq $lineInput) {
      Start-Sleep -Seconds 3
      return $null
    }
    $trimmedInput = $lineInput.Trim().ToUpperInvariant()
    $mappedKeyName = switch ($trimmedInput) {
      "" { "Enter" }
      "Q" { "Q" }
      "R" { "R" }
      "K" { "K" }
      "X" { "X" }
      "J" { "DownArrow" }
      default { $trimmedInput }
    }
    return $mappedKeyName
  }
}

function Stop-SelectedDevServerTree {
  param(
    [array]$ServersList,
    [int]$SelectedIndex
  )
  $selectedServer = $ServersList[$SelectedIndex]
  $targetRootPid = [int]$selectedServer.rootPid
  if ($targetRootPid -gt 0) {
    try {
      & taskkill.exe /T /F /PID $targetRootPid *>$null
    } catch {
      Write-DevServerLog -Level "WARN" -Operation "stop_server_taskkill" -Message "pid=$targetRootPid error=$($_.Exception.Message)"
    }
    foreach ($childPid in @($selectedServer.childPids)) {
      Stop-Process -Id ([int]$childPid) -Force -ErrorAction SilentlyContinue
    }
    Stop-Process -Id $targetRootPid -Force -ErrorAction SilentlyContinue
  }

  $remainingServersList = @($ServersList | Where-Object { [int]$_.rootPid -ne $targetRootPid })
  $updatedSnapshot = [PSCustomObject]@{
    updatedAtUnixMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    servers         = $remainingServersList
  }
  $updatedSnapshotJson = $updatedSnapshot | ConvertTo-Json -Depth 6
  $updatedBadgeText = if ($remainingServersList.Count -gt 0) { "DEV: ON" } else { "DEV: OFF" }
  Write-AtomicTextFile -TargetPath $snapshotFilePath -Content "$updatedSnapshotJson`n"
  Write-AtomicTextFile -TargetPath $badgeFilePath -Content "$updatedBadgeText`n"
  Write-DevServerLog -Level "INFO" -Operation "stop_server_tree" -Message "kind=$($selectedServer.kind) rootPid=$targetRootPid remainingCount=$($remainingServersList.Count)"

  return [PSCustomObject]@{
    RemainingServers    = $remainingServersList
    StatusBannerMessage = "Stopped $($selectedServer.kind) (PID $targetRootPid)."
  }
}

function Set-HerdrServerFocus {
  param($ServerRecord)
  $workspaceId = [string]$ServerRecord.workspaceId
  if ([string]::IsNullOrWhiteSpace($workspaceId)) {
    return [PSCustomObject]@{
      Focused             = $false
      StatusBannerMessage = "Selected server has no associated Herdr workspace."
    }
  }

  $herdrExecutable = Resolve-HerdrBinary
  if (-not $herdrExecutable) {
    $herdrExecutable = "herdr.exe"
  }

  try {
    & $herdrExecutable workspace focus $workspaceId *>$null
  } catch {
    Write-DevServerLog -Level "WARN" -Operation "focus_workspace" -Message "workspaceId=$workspaceId error=$($_.Exception.Message)"
  }

  $targetPaneId = [string]$ServerRecord.paneId
  if (-not [string]::IsNullOrWhiteSpace($targetPaneId) -and $targetPaneId -ne "-") {
    try {
      & $herdrExecutable pane focus $targetPaneId *>$null
      if ($LASTEXITCODE -ne 0) {
        & $herdrExecutable agent focus $targetPaneId *>$null
      }
    } catch {
      Write-DevServerLog -Level "WARN" -Operation "focus_pane" -Message "paneId=$targetPaneId error=$($_.Exception.Message)"
    }
  }

  Write-DevServerLog -Level "INFO" -Operation "focus_server" -Message "workspaceId=$workspaceId paneId=$targetPaneId"
  return [PSCustomObject]@{
    Focused             = $true
    StatusBannerMessage = ""
  }
}

function Invoke-DevServersOverlayPane {
  $escapeCharacter = [char]27
  $selectedIndex = 0
  $statusBannerMessage = ""
  $snapshot = $null
  $serversList = @()
  $lastSnapshotWriteUtc = [DateTime]::MinValue
  $shouldReloadCachedSnapshot = $false

  [Console]::Write("$escapeCharacter[?25l$escapeCharacter[2J$escapeCharacter[H")
  try {
    while ($true) {
      $currentSnapshotWriteUtc = Get-SnapshotLastWriteTimeUtc

      if ($shouldReloadCachedSnapshot -or $null -eq $snapshot -or ($currentSnapshotWriteUtc -ne $lastSnapshotWriteUtc)) {
        $snapshot = Read-CachedDevServersSnapshot
        $serversList = @($snapshot.servers)
        $lastSnapshotWriteUtc = $currentSnapshotWriteUtc
        $shouldReloadCachedSnapshot = $false
      }

      if ($selectedIndex -ge $serversList.Count) {
        $selectedIndex = [Math]::Max(0, $serversList.Count - 1)
      }

      $boardFrame = Format-DevServersBoardFrame `
        -ServersList $serversList `
        -SelectedIndex $selectedIndex `
        -StatusBannerMessage $statusBannerMessage
      $statusBannerMessage = ""
      [Console]::Write($boardFrame)

      $pressedKeyName = Read-OverlayCommandKey -LastSnapshotWriteUtc $lastSnapshotWriteUtc
      if ($null -eq $pressedKeyName) {
        continue
      }

      switch ($pressedKeyName) {
        { $_ -in @("Q", "Escape") } {
          return
        }
        "R" {
          $shouldReloadCachedSnapshot = $true
          $statusBannerMessage = "Refreshed server list."
        }
        "UpArrow" {
          if ($selectedIndex -gt 0) { $selectedIndex-- }
        }
        { $_ -in @("DownArrow", "J") } {
          if ($selectedIndex -lt ($serversList.Count - 1)) { $selectedIndex++ }
        }
        { $_ -in @("K", "X") } {
          if ($serversList.Count -gt 0) {
            $stopOutcome = Stop-SelectedDevServerTree -ServersList $serversList -SelectedIndex $selectedIndex
            $serversList = @($stopOutcome.RemainingServers)
            $lastSnapshotWriteUtc = Get-SnapshotLastWriteTimeUtc
            $statusBannerMessage = $stopOutcome.StatusBannerMessage
          }
        }
        "Enter" {
          if ($serversList.Count -gt 0) {
            $focusOutcome = Set-HerdrServerFocus -ServerRecord $serversList[$selectedIndex]
            if ($focusOutcome.Focused) {
              return
            }
            $statusBannerMessage = $focusOutcome.StatusBannerMessage
          }
        }
      }
    }
  } finally {
    [Console]::Write("$escapeCharacter[?25h")
  }
}
