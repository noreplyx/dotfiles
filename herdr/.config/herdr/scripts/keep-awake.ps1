# On-demand screen & system idle sleep inhibitor for Herdr on Windows (prefix+shift+a).
# Usage: keep-awake.ps1 [--toggle|--on|--off|--status|--badge|--daemon <0|1>|--hold-sentinel <path>]

$ErrorActionPreference = "Stop"

$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$cacheDir = Join-Path $homeDir ".cache"
if (-not (Test-Path -LiteralPath $cacheDir)) {
  New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
}
$stateFilePath = Join-Path $cacheDir "herdr-keep-awake"
$badgeFilePath = Join-Path $cacheDir "herdr-keep-awake.badge"
$watchdogPidFilePath = Join-Path $cacheDir "herdr-keep-awake.pid"
$logFilePath = Join-Path $cacheDir "herdr-keep-awake.log"

function Write-AtomicTextFile {
  param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][string]$Content
  )
  $utf8WithoutByteOrderMark = [System.Text.UTF8Encoding]::new($false)
  $tempFile = "$TargetPath.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"
  try {
    [System.IO.File]::WriteAllText($tempFile, $Content, $utf8WithoutByteOrderMark)
    if ([System.IO.File]::Exists($TargetPath)) {
      [System.IO.File]::Replace($tempFile, $TargetPath, $null)
    } else {
      [System.IO.File]::Move($tempFile, $TargetPath)
    }
  } catch {
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    try {
      [System.IO.File]::WriteAllText($TargetPath, $Content, $utf8WithoutByteOrderMark)
    } catch {}
  }
}

function Read-TextFileTrimmedWithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [int]$MaxAttempts = 3,
    [int]$RetryDelayMilliseconds = 15
  )
  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    if (-not [System.IO.File]::Exists($TargetPath)) {
      return $null
    }
    try {
      return ([System.IO.File]::ReadAllText($TargetPath)).Trim()
    } catch {
      if ($attempt -lt $MaxAttempts) {
        Start-Sleep -Milliseconds $RetryDelayMilliseconds
      }
    }
  }
  return $null
}

function Write-KeepAwakeLog {
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

function Write-KeepAwakeState {
  param([string]$State)
  $normalizedState = if ($State -and $State.Trim().ToUpperInvariant() -eq "ON") { "ON" } else { "OFF" }
  Write-AtomicTextFile -TargetPath $stateFilePath -Content "$normalizedState`n"
  Write-AtomicTextFile -TargetPath $badgeFilePath -Content "AWAKE: $normalizedState`n"
}

function Get-ActiveDaemonProcess {
  param([int]$KnownProcessId = 0)
  $parsedProcessId = $KnownProcessId
  if ($parsedProcessId -le 0) {
    $rawProcessId = Read-TextFileTrimmedWithRetry -TargetPath $watchdogPidFilePath
    if ([string]::IsNullOrWhiteSpace($rawProcessId) -or $rawProcessId -eq "starting") {
      return $null
    }
    if ($rawProcessId.StartsWith("win:")) {
      $rawProcessId = $rawProcessId.Substring(4).Trim()
    }
    if (-not [int]::TryParse($rawProcessId, [ref]$parsedProcessId) -or $parsedProcessId -le 0) {
      return $null
    }
  }
  $daemonProcess = Get-Process -Id $parsedProcessId -ErrorAction SilentlyContinue
  if ($null -ne $daemonProcess -and $daemonProcess.ProcessName -in @('powershell', 'pwsh')) {
    return $daemonProcess
  }
  return $null
}

function Test-KeepAwakeActive {
  if (-not [System.IO.File]::Exists($watchdogPidFilePath)) {
    return $false
  }
  $rawDaemonToken = Read-TextFileTrimmedWithRetry -TargetPath $watchdogPidFilePath
  if ([string]::IsNullOrWhiteSpace($rawDaemonToken)) {
    return $false
  }
  if ($rawDaemonToken -eq "starting" -or $rawDaemonToken.StartsWith("starting:", [System.StringComparison]::OrdinalIgnoreCase)) {
    try {
      if (([DateTime]::UtcNow - [System.IO.File]::GetLastWriteTimeUtc($watchdogPidFilePath)).TotalSeconds -lt 20) {
        return $true
      }
    } catch {}
    return $false
  }
  return $null -ne (Get-ActiveDaemonProcess)
}

function Test-HerdrProcessRunning {
  return $null -ne (Get-Process -Name "herdr*" -ErrorAction SilentlyContinue)
}

function Start-DetachedKeepAwakeDaemon {
  param([string]$StartedWithHerdrFlag = "1")
  Write-AtomicTextFile -TargetPath $watchdogPidFilePath -Content "starting`n"
  Write-KeepAwakeLog -Level "INFO" -Operation "daemon_spawn_requested" -Message "startedWithHerdr=$StartedWithHerdrFlag"

  $powerShellExecutable = Join-Path $PSHOME "powershell.exe"
  if (-not (Test-Path -LiteralPath $powerShellExecutable)) {
    $currentProcessPath = (Get-Process -Id $PID -ErrorAction SilentlyContinue).Path
    if ($currentProcessPath -and (Test-Path -LiteralPath $currentProcessPath)) {
      $powerShellExecutable = $currentProcessPath
    } else {
      $powerShellExecutable = "powershell.exe"
    }
  }

  $isDaemonSpawned = $false
  $spawnedProcessId = 0

  try {
    $daemonProcess = Start-Process -FilePath $powerShellExecutable -WorkingDirectory $homeDir -WindowStyle Hidden -PassThru -ArgumentList @(
      "-NoLogo",
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      "`"$PSCommandPath`"",
      "--daemon",
      $StartedWithHerdrFlag
    ) -ErrorAction Stop
    if ($null -ne $daemonProcess -and $daemonProcess.Id -gt 0) {
      $spawnedProcessId = [int]$daemonProcess.Id
      $isDaemonSpawned = $true
      Write-KeepAwakeLog -Level "INFO" -Operation "daemon_spawn_startprocess" -Message "spawnedPid=$spawnedProcessId"
    }
  } catch {
    Write-KeepAwakeLog -Level "WARN" -Operation "daemon_spawn_startprocess" -Message "error=$($_.Exception.Message)"
  }

  if (-not $isDaemonSpawned) {
    $escapedPowerShellExecutablePath = $powerShellExecutable.Replace('"', '\"')
    $escapedScriptPath = $PSCommandPath.Replace('"', '\"')
    $daemonCommandLine = "`"$escapedPowerShellExecutablePath`" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$escapedScriptPath`" --daemon $StartedWithHerdrFlag"

    try {
      $startupInformation = New-CimInstance -ClassName Win32_ProcessStartup -Property @{ ShowWindow = [uint16]0 } -ClientOnly
      $createResult = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine               = $daemonCommandLine
        CurrentDirectory          = $homeDir
        ProcessStartupInformation = $startupInformation
      } -ErrorAction Stop
      if ($null -ne $createResult -and [uint32]$createResult.ReturnValue -eq 0 -and $createResult.ProcessId) {
        $spawnedProcessId = [int]$createResult.ProcessId
        $isDaemonSpawned = $true
        Write-KeepAwakeLog -Level "INFO" -Operation "daemon_spawn_cim" -Message "spawnedPid=$spawnedProcessId"
      }
    } catch {
      Write-KeepAwakeLog -Level "WARN" -Operation "daemon_spawn_cim" -Message "error=$($_.Exception.Message)"
    }
  }

  if ($isDaemonSpawned -and $spawnedProcessId -gt 0) {
    Write-AtomicTextFile -TargetPath $watchdogPidFilePath -Content "win:$spawnedProcessId`n"
    return $true
  }

  Remove-Item -LiteralPath $watchdogPidFilePath -Force -ErrorAction SilentlyContinue
  return $false
}

function Clear-StaleKeepAwakeState {
  if ((Test-Path -LiteralPath $watchdogPidFilePath) -and -not (Test-KeepAwakeActive)) {
    Remove-Item -LiteralPath $watchdogPidFilePath -Force -ErrorAction SilentlyContinue
    Write-KeepAwakeState "OFF"
  }
}

# Fast-path status badge (<5ms; pure lock-free cache reader; liveness reconciliation is deferred to --status/--toggle).
if ($args.Count -ge 1 -and [string]$args[0] -in @("--badge", "badge")) {
  $rawBadgeText = Read-TextFileTrimmedWithRetry -TargetPath $badgeFilePath
  if (-not [string]::IsNullOrWhiteSpace($rawBadgeText)) {
    Write-Output $rawBadgeText
    exit 0
  }
  $cachedStateText = Read-TextFileTrimmedWithRetry -TargetPath $stateFilePath
  $normalizedState = if ($null -ne $cachedStateText) { $cachedStateText.ToUpperInvariant() } else { "OFF" }
  if ($normalizedState -eq "ON") {
    Write-Output "AWAKE: ON"
  } else {
    Write-Output "AWAKE: OFF"
  }
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
  $standalonePath = Join-Path $homeDir ".herdr\packages\standalone\current\herdr.exe"
  if (Test-Path -LiteralPath $standalonePath) {
    return $standalonePath
  }
  $binPath = Join-Path $homeDir ".herdr\bin\herdr.exe"
  if (Test-Path -LiteralPath $binPath) {
    return $binPath
  }
  return $null
}

function Clear-LeftoverWorkspaceBadges {
  param([string]$HerdrBinaryPath)
  if (-not $HerdrBinaryPath) {
    return
  }
  $sidebarClearedSentinel = Join-Path $cacheDir "herdr-keep-awake-sidebar-cleared"
  if ([System.IO.File]::Exists($sidebarClearedSentinel)) {
    return
  }
  $sessionPath = if ($env:APPDATA) {
    Join-Path $env:APPDATA "herdr\session.json"
  } else {
    Join-Path $homeDir "AppData\Roaming\herdr\session.json"
  }
  if (Test-Path -LiteralPath $sessionPath) {
    try {
      $sessionRaw = [System.IO.File]::ReadAllText($sessionPath)
      $matchesFound = [regex]::Matches($sessionRaw, '"id"\s*:\s*"(w[^"]+)"')
      $workspaceIds = @($matchesFound | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
      foreach ($workspaceId in $workspaceIds) {
        try {
          & $HerdrBinaryPath workspace report-metadata $workspaceId --source keep-awake --clear-token keep_awake *>$null
        } catch {}
      }
    } catch {}
  }
  try {
    [System.IO.File]::WriteAllText($sidebarClearedSentinel, "1`n")
  } catch {}
}

function Send-KeepAwakeNotification {
  param(
    [string]$State,
    [switch]$Synchronous
  )
  $herdrBinaryPath = Resolve-HerdrBinary
  if (-not $herdrBinaryPath) {
    return
  }
  if ($Synchronous) {
    try {
      & $herdrBinaryPath notification show "Keep-Awake: $State" --body "Screen & system idle sleep inhibition is $State" --position top-right --sound none *>$null
    } catch {}
    Clear-LeftoverWorkspaceBadges -HerdrBinaryPath $herdrBinaryPath
    return
  }
  try {
    Start-Process -FilePath $herdrBinaryPath -WindowStyle Hidden -ArgumentList @(
      "notification",
      "show",
      "Keep-Awake: $State",
      "--body",
      "Screen & system idle sleep inhibition is $State",
      "--position",
      "top-right",
      "--sound",
      "none"
    ) -ErrorAction SilentlyContinue | Out-Null
  } catch {}
}

function Get-PowerExecutionStateType {
  if ("HerdrKeepAwake.Power" -as [type]) {
    return [HerdrKeepAwake.Power]
  }
  $memberDefinition = @'
[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
public static extern uint SetThreadExecutionState(uint executionStateFlags);
public static void Hold() { SetThreadExecutionState(0x80000003u); }
public static void Release() { SetThreadExecutionState(0x80000000u); }
'@
  return Add-Type -MemberDefinition $memberDefinition -Name 'Power' -Namespace 'HerdrKeepAwake' -PassThru
}

function Wait-SentinelHoldInterval([string]$SentinelPath) {
  for ($tick = 0; $tick -lt 60; $tick++) {
    if (-not [System.IO.File]::Exists($SentinelPath)) {
      break
    }
    $stateText = Read-TextFileTrimmedWithRetry -TargetPath $stateFilePath
    if ($null -ne $stateText -and $stateText.ToUpperInvariant() -eq "OFF") {
      break
    }
    Start-Sleep -Milliseconds 50
  }
}

function Invoke-KeepAwakeDaemon {
  param([string]$StartedWithHerdrFlag)
  $initialStateText = Read-TextFileTrimmedWithRetry -TargetPath $stateFilePath
  if (($null -ne $initialStateText -and $initialStateText.ToUpperInvariant() -eq "OFF") -or -not [System.IO.File]::Exists($watchdogPidFilePath)) {
    Write-KeepAwakeLog -Level "INFO" -Operation "daemon_aborted_off" -Message "keep-awake already OFF before daemon loop"
    return
  }
  $hasObservedHerdrProcess = ($StartedWithHerdrFlag -eq "1") -or (Test-HerdrProcessRunning)
  Write-AtomicTextFile -TargetPath $watchdogPidFilePath -Content "win:$PID`n"
  Write-KeepAwakeLog -Level "INFO" -Operation "daemon_started" -Message "startedWithHerdrFlag=$StartedWithHerdrFlag hasObservedHerdr=$hasObservedHerdrProcess"
  $powerType = Get-PowerExecutionStateType
  $powerType::Hold()
  Send-KeepAwakeNotification -State "ON" -Synchronous
  try {
    while ([System.IO.File]::Exists($watchdogPidFilePath)) {
      $currentStateText = Read-TextFileTrimmedWithRetry -TargetPath $stateFilePath
      if ($null -ne $currentStateText -and $currentStateText.ToUpperInvariant() -eq "OFF") {
        Write-KeepAwakeLog -Level "INFO" -Operation "daemon_state_off" -Message "state file set to OFF"
        break
      }
      $currentToken = Read-TextFileTrimmedWithRetry -TargetPath $watchdogPidFilePath
      if (
        -not [string]::IsNullOrWhiteSpace($currentToken) -and
        $currentToken -ne "starting" -and
        (-not $currentToken.StartsWith("starting:", [System.StringComparison]::OrdinalIgnoreCase)) -and
        $currentToken -ne "win:$PID" -and
        $currentToken -ne "$PID"
      ) {
        Write-KeepAwakeLog -Level "INFO" -Operation "daemon_superseded" -Message "currentToken=$currentToken"
        break
      }
      if (-not $hasObservedHerdrProcess -and (Test-HerdrProcessRunning)) {
        $hasObservedHerdrProcess = $true
      }
      if ($hasObservedHerdrProcess -and -not (Test-HerdrProcessRunning)) {
        Write-KeepAwakeLog -Level "INFO" -Operation "daemon_herdr_exited" -Message "all herdr processes exited"
        break
      }
      $powerType::Hold()
      Wait-SentinelHoldInterval -SentinelPath $watchdogPidFilePath
    }
  } finally {
    $powerType::Release()
    if ([System.IO.File]::Exists($watchdogPidFilePath)) {
      $latestToken = Read-TextFileTrimmedWithRetry -TargetPath $watchdogPidFilePath
      if ($latestToken -eq "win:$PID" -or $latestToken -eq "$PID") {
        Remove-Item -LiteralPath $watchdogPidFilePath -Force -ErrorAction SilentlyContinue
        Write-KeepAwakeState "OFF"
      }
    } else {
      Write-KeepAwakeState "OFF"
    }
    Write-KeepAwakeLog -Level "INFO" -Operation "daemon_stopped" -Message "released execution state"
  }
}

function Invoke-SentinelHold {
  param([string]$SentinelPath)
  if ([string]::IsNullOrWhiteSpace($SentinelPath)) {
    return
  }
  $powerType = Get-PowerExecutionStateType
  try {
    while ([System.IO.File]::Exists($SentinelPath)) {
      $powerType::Hold()
      Wait-SentinelHoldInterval -SentinelPath $SentinelPath
    }
  } finally {
    $powerType::Release()
  }
}

function Enable-KeepAwake {
  Clear-StaleKeepAwakeState
  if (Test-KeepAwakeActive) {
    Write-KeepAwakeState "ON"
    Send-KeepAwakeNotification -State "ON"
    Write-Output "ON"
    return
  }

  $startedWithHerdrFlag = if (Test-HerdrProcessRunning) { "1" } else { "0" }
  Write-KeepAwakeState "ON"
  if (-not (Start-DetachedKeepAwakeDaemon -StartedWithHerdrFlag $startedWithHerdrFlag)) {
    Write-KeepAwakeState "OFF"
    if (Test-Path -LiteralPath $watchdogPidFilePath) {
      Remove-Item -LiteralPath $watchdogPidFilePath -Force -ErrorAction SilentlyContinue
    }
    Write-Output "OFF"
    exit 1
  }
  Write-Output "ON"
}

function Disable-KeepAwake {
  $daemonProcess = Get-ActiveDaemonProcess
  Write-KeepAwakeState "OFF"
  Write-KeepAwakeLog -Level "INFO" -Operation "keep_awake_disabled" -Message "targetPid=$(if ($daemonProcess) { $daemonProcess.Id } else { 0 })"
  Send-KeepAwakeNotification -State "OFF"

  if ($null -ne $daemonProcess -and $daemonProcess.ProcessName -in @('powershell', 'pwsh')) {
    $hasExitedCleanly = $false
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
      if ($daemonProcess.HasExited) {
        $hasExitedCleanly = $true
        break
      }
      Start-Sleep -Milliseconds 50
    }
    if (-not $hasExitedCleanly -and -not $daemonProcess.HasExited) {
      Stop-Process -Id $daemonProcess.Id -Force -ErrorAction SilentlyContinue
    }
  }

  if (Test-Path -LiteralPath $watchdogPidFilePath) {
    Remove-Item -LiteralPath $watchdogPidFilePath -Force -ErrorAction SilentlyContinue
  }
  Write-Output "OFF"
}

$action = if ($args.Count -ge 1) { [string]$args[0] } else { "--toggle" }
switch ($action) {
  "--toggle" {
    Clear-StaleKeepAwakeState
    if (Test-KeepAwakeActive) {
      Disable-KeepAwake
    } else {
      Enable-KeepAwake
    }
  }
  "--on" {
    Enable-KeepAwake
  }
  "--off" {
    Disable-KeepAwake
  }
  "--status" {
    Clear-StaleKeepAwakeState
    if (Test-KeepAwakeActive) {
      Write-KeepAwakeState "ON"
      Write-Output "ON"
    } else {
      Write-KeepAwakeState "OFF"
      Write-Output "OFF"
    }
  }
  "--daemon" {
    $startedWithHerdrFlag = if ($args.Count -ge 2) { [string]$args[1] } else { "0" }
    Invoke-KeepAwakeDaemon -StartedWithHerdrFlag $startedWithHerdrFlag
  }
  "--hold-sentinel" {
    $sentinelPath = if ($args.Count -ge 2) { [string]$args[1] } else { "" }
    Invoke-SentinelHold -SentinelPath $sentinelPath
  }
  default {
    [Console]::Error.WriteLine("usage: keep-awake.ps1 [--toggle|--on|--off|--status|--badge]")
    exit 1
  }
}
