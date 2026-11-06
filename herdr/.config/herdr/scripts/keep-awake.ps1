# On-demand screen & system idle sleep inhibitor for Herdr on Windows (prefix+shift+a).
# Usage: keep-awake.ps1 [--toggle|--on|--off|--status|--badge|--daemon <0|1>|--hold-sentinel <path>]

$ErrorActionPreference = "Stop"

$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$cacheDir = Join-Path $homeDir ".cache"
if (-not (Test-Path -LiteralPath $cacheDir)) {
  New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
}
$stateFile = Join-Path $cacheDir "herdr-keep-awake"
$watchdogPidFile = Join-Path $cacheDir "herdr-keep-awake.pid"

if ($args.Count -ge 1 -and [string]$args[0] -eq "--badge") {
  if ([System.IO.File]::Exists($stateFile) -and [System.IO.File]::Exists($watchdogPidFile)) {
    try {
      if (([System.IO.File]::ReadAllText($stateFile)).Trim().ToUpperInvariant() -eq "ON") {
        Write-Output "AWAKE: ON"
        exit 0
      }
    } catch {}
  }
  Write-Output "AWAKE: OFF"
  exit 0
}

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

function Write-KeepAwakeState {
  param([string]$State)
  Write-AtomicTextFile -TargetPath $stateFile -Content "$State`n"
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

function Get-ActiveDaemonProcess {
  param([int]$KnownProcessId = 0)
  $parsedProcessId = $KnownProcessId
  if ($parsedProcessId -le 0) {
    if (-not (Test-Path -LiteralPath $watchdogPidFile)) {
      return $null
    }
    $rawProcessId = ""
    try {
      $firstLine = Get-Content -LiteralPath $watchdogPidFile -TotalCount 1 -ErrorAction SilentlyContinue
      if ($null -ne $firstLine) {
        $rawProcessId = ([string]$firstLine).Trim()
      }
    } catch {
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
  return $null -ne (Get-ActiveDaemonProcess)
}

function Clear-StaleKeepAwakeState {
  if ((Test-Path -LiteralPath $watchdogPidFile) -and -not (Test-KeepAwakeActive)) {
    Remove-Item -LiteralPath $watchdogPidFile -Force -ErrorAction SilentlyContinue
    Write-KeepAwakeState "OFF"
  }
}

function Get-KeepAwakeBadgeText {
  Clear-StaleKeepAwakeState
  if (Test-Path -LiteralPath $stateFile) {
    try {
      if (([System.IO.File]::ReadAllText($stateFile)).Trim().ToUpperInvariant() -eq "ON") {
        return "AWAKE: ON"
      }
    } catch {}
  }
  if (Test-KeepAwakeActive) {
    return "AWAKE: ON"
  }
  return "AWAKE: OFF"
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
  param([string]$State)
  $herdrBinaryPath = Resolve-HerdrBinary
  if ($herdrBinaryPath) {
    try {
      & $herdrBinaryPath notification show "Keep-Awake: $State" --body "Screen & system idle sleep inhibition is $State" --position top-right --sound none *>$null
    } catch {}
    Clear-LeftoverWorkspaceBadges -HerdrBinaryPath $herdrBinaryPath
  }
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
  for ($tick = 0; $tick -lt 15; $tick++) {
    if (-not [System.IO.File]::Exists($SentinelPath)) {
      break
    }
    Start-Sleep -Milliseconds 200
  }
}

function Invoke-KeepAwakeDaemon {
  param([string]$StartedWithHerdrFlag)
  $startedWithHerdr = ($StartedWithHerdrFlag -eq "1")
  $powerType = Get-PowerExecutionStateType
  try {
    while ([System.IO.File]::Exists($watchdogPidFile)) {
      $currentToken = ""
      try {
        $currentToken = ([System.IO.File]::ReadAllText($watchdogPidFile)).Trim()
      } catch {}
      if ($currentToken -ne "starting" -and $currentToken -ne "win:$PID") {
        break
      }
      if ($startedWithHerdr -and -not (Get-Process -Name "herdr" -ErrorAction SilentlyContinue)) {
        if ([System.IO.File]::Exists($watchdogPidFile)) {
          try {
            $latestToken = ([System.IO.File]::ReadAllText($watchdogPidFile)).Trim()
            if ($latestToken -eq "win:$PID" -or $latestToken -eq "$PID") {
              Remove-Item -LiteralPath $watchdogPidFile -Force -ErrorAction SilentlyContinue
              Write-KeepAwakeState "OFF"
            }
          } catch {}
        }
        break
      }
      $powerType::Hold()
      Wait-SentinelHoldInterval -SentinelPath $watchdogPidFile
    }
  } finally {
    $powerType::Release()
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
    Send-KeepAwakeNotification "ON"
    Write-Output "ON"
    return
  }

  $startedWithHerdrFlag = if (Get-Process -Name "herdr" -ErrorAction SilentlyContinue) { "1" } else { "0" }
  Write-KeepAwakeState "ON"
  Write-AtomicTextFile -TargetPath $watchdogPidFile -Content "starting`n"
  Send-KeepAwakeNotification "ON"

  $powerShellExecutablePath = (Get-Process -Id $PID).Path
  if (-not $powerShellExecutablePath) { $powerShellExecutablePath = "powershell.exe" }
  $daemonProcess = Start-Process -FilePath $powerShellExecutablePath -WorkingDirectory $homeDir -WindowStyle Hidden -ArgumentList @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath, "--daemon", $startedWithHerdrFlag) -PassThru

  Write-AtomicTextFile -TargetPath $watchdogPidFile -Content "win:$($daemonProcess.Id)`n"
  Write-Output "ON"
}

function Disable-KeepAwake {
  $daemonProcess = Get-ActiveDaemonProcess
  if (Test-Path -LiteralPath $watchdogPidFile) {
    Remove-Item -LiteralPath $watchdogPidFile -Force -ErrorAction SilentlyContinue
  }
  Write-KeepAwakeState "OFF"
  Send-KeepAwakeNotification "OFF"
  if ($null -ne $daemonProcess) {
    $targetProcessId = $daemonProcess.Id
    for ($pollAttempt = 0; $pollAttempt -lt 4; $pollAttempt++) {
      Start-Sleep -Milliseconds 100
      $daemonProcess = Get-ActiveDaemonProcess -KnownProcessId $targetProcessId
      if ($null -eq $daemonProcess) {
        break
      }
    }
    if ($null -ne $daemonProcess -and $daemonProcess.ProcessName -in @('powershell', 'pwsh')) {
      Stop-Process -Id $daemonProcess.Id -Force -ErrorAction SilentlyContinue
    }
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
  "--badge" {
    Write-Output (Get-KeepAwakeBadgeText)
  }
  "--daemon" {
    $herdrFlag = if ($args.Count -ge 2) { [string]$args[1] } else { "0" }
    Invoke-KeepAwakeDaemon -StartedWithHerdrFlag $herdrFlag
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
