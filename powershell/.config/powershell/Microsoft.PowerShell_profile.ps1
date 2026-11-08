# PowerShell 7 Interactive Profile
# Canonical XDG location: ~/.config/powershell/Microsoft.PowerShell_profile.ps1

if ([Environment]::UserInteractive -eq $false -or $Host.Name -ne 'ConsoleHost') {
    return
}

$script:IsProfileTimingEnabled = ($env:PWSH_PROFILE_TIMING -eq '1' -or $env:PWSH_PROFILE_TIMING -eq 'true')
$script:ProfileTotalStopwatch = if ($script:IsProfileTimingEnabled) { [System.Diagnostics.Stopwatch]::StartNew() } else { $null }
$script:ProfileSectionTimings = if ($script:IsProfileTimingEnabled) { [System.Collections.Generic.List[pscustomobject]]::new() } else { $null }

function Write-ProfileTiming {
    param(
        [Parameter(Mandatory = $true)][string]$SectionName,
        [AllowNull()][nullable[long]]$StartTimestamp,
        [string]$Outcome = 'ok'
    )
    if (-not $script:IsProfileTimingEnabled -or $null -eq $StartTimestamp) {
        return
    }
    $elapsedTicks = [System.Diagnostics.Stopwatch]::GetTimestamp() - $StartTimestamp
    $durationMs = [Math]::Round(($elapsedTicks * 1000.0) / [System.Diagnostics.Stopwatch]::Frequency, 2)
    $script:ProfileSectionTimings.Add([pscustomobject]@{
        Section    = $SectionName
        Outcome    = $Outcome
        DurationMs = $durationMs
    })
}

# ── 1. Environment & Deduplicated PATH ────────────────────────────────────────

$sectionStart = if ($script:IsProfileTimingEnabled) { [System.Diagnostics.Stopwatch]::GetTimestamp() } else { $null }

if (-not $env:XDG_CONFIG_HOME) {
    $env:XDG_CONFIG_HOME = Join-Path $HOME '.config'
}
$env:EDITOR = 'nvim'
if (-not $env:BUN_INSTALL) {
    $env:BUN_INSTALL = Join-Path $HOME '.bun'
}

$pathSeparator = [System.IO.Path]::PathSeparator
$pathComparer = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    [System.StringComparer]::OrdinalIgnoreCase
} else {
    [System.StringComparer]::Ordinal
}

$priorityDirectories = @(
    (Join-Path $HOME '.local\bin'),
    (Join-Path $HOME '.opencode\bin'),
    (Join-Path $env:BUN_INSTALL 'bin')
)

$seenDirectories = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
$orderedDirectories = [System.Collections.Generic.List[string]]::new()

foreach ($directory in $priorityDirectories) {
    $normalized = $directory.TrimEnd('\', '/')
    if ($normalized -and $seenDirectories.Add($normalized)) {
        $orderedDirectories.Add($directory)
    }
}

if ($env:PATH) {
    foreach ($entry in $env:PATH.Split($pathSeparator, [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $normalized = $entry.TrimEnd('\', '/')
        if ($normalized -and $seenDirectories.Add($normalized)) {
            $orderedDirectories.Add($entry)
        }
    }
}

$env:PATH = [string]::Join($pathSeparator, $orderedDirectories)

Write-ProfileTiming -SectionName 'Environment' -StartTimestamp $sectionStart

# ── 2. Binary-Mtime-Invalidated Disk Cache Engine ─────────────────────────────

$script:PowerShellCacheDirectory = if ($env:XDG_CACHE_HOME) {
    Join-Path $env:XDG_CACHE_HOME 'powershell'
} else {
    Join-Path $HOME '.cache\powershell'
}

function Resolve-CachedInitScript {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Generator,
        [string]$CacheKey = $Name
    )

    $commandInfo = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $commandInfo -or -not $commandInfo.Source) {
        return $null
    }

    if (-not [System.IO.Directory]::Exists($script:PowerShellCacheDirectory)) {
        [void][System.IO.Directory]::CreateDirectory($script:PowerShellCacheDirectory)
    }

    $cacheFilePath = Join-Path $script:PowerShellCacheDirectory "$CacheKey-init.ps1"
    $binaryFileInfo = [System.IO.FileInfo]::new($commandInfo.Source)
    $cacheFileInfo = [System.IO.FileInfo]::new($cacheFilePath)

    $isCacheStale = (-not $cacheFileInfo.Exists) -or
        ($cacheFileInfo.Length -eq 0) -or
        ($binaryFileInfo.LastWriteTimeUtc -gt $cacheFileInfo.LastWriteTimeUtc)

    if ($isCacheStale) {
        $tempFilePath = "$cacheFilePath.$PID.tmp"
        try {
            $generatedLines = & $Generator
            $generatedScript = ($generatedLines -join [Environment]::NewLine).Trim()
            if ($generatedScript) {
                $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllText($tempFilePath, $generatedScript + [Environment]::NewLine, $utf8NoBom)
                Move-Item -LiteralPath $tempFilePath -Destination $cacheFilePath -Force
            }
        } catch {
            Write-Warning "[Resolve-CachedInitScript] Failed to generate init cache for '$Name': $($_.Exception.Message)"
            if ([System.IO.File]::Exists($tempFilePath)) {
                Remove-Item -LiteralPath $tempFilePath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if ([System.IO.File]::Exists($cacheFilePath)) {
        return $cacheFilePath
    }
    return $null
}

# ── 3. Cached CLI Initializations & WezTerm OSC 7 / KB Integration ────────────

$sectionStart = if ($script:IsProfileTimingEnabled) { [System.Diagnostics.Stopwatch]::GetTimestamp() } else { $null }

$starshipInitPath = Resolve-CachedInitScript -Name 'starship' -Generator { & starship init powershell --print-full-init }
if ($starshipInitPath) { . $starshipInitPath }

$zoxideInitPath = Resolve-CachedInitScript -Name 'zoxide' -Generator { & zoxide init powershell }
if ($zoxideInitPath) { . $zoxideInitPath }

$fnmInitPath = Resolve-CachedInitScript -Name 'fnm' -Generator { & fnm env --use-on-cd --shell powershell }
if ($fnmInitPath) { . $fnmInitPath }

$userHomeDirectory = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$script:HerdrShellCacheDirectory = Join-Path $userHomeDirectory '.cache\herdr-shells'
$script:HerdrShellTelemetryFilePath = Join-Path $script:HerdrShellCacheDirectory "$PID.json"
$global:LastTrackedHerdrWorkingDirectory = ''

function Publish-HerdrShellTelemetry {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentDirectoryPath
    )
    if ($CurrentDirectoryPath -eq $global:LastTrackedHerdrWorkingDirectory) {
        return
    }
    $global:LastTrackedHerdrWorkingDirectory = $CurrentDirectoryPath
    try {
        if (-not [System.IO.Directory]::Exists($script:HerdrShellCacheDirectory)) {
            [void][System.IO.Directory]::CreateDirectory($script:HerdrShellCacheDirectory)
        }
        $paneId = if ($env:HERDR_PANE_ID) { $env:HERDR_PANE_ID } elseif ($env:HERDR_PANE) { $env:HERDR_PANE } else { '' }
        $workspaceId = if ($env:HERDR_WORKSPACE_ID) { $env:HERDR_WORKSPACE_ID } elseif ($env:HERDR_WORKSPACE) { $env:HERDR_WORKSPACE } else { '' }
        $escapedPaneId = $paneId.Replace('\', '\\').Replace('"', '\"')
        $escapedWorkspaceId = $workspaceId.Replace('\', '\\').Replace('"', '\"')
        $escapedDirectoryPath = $CurrentDirectoryPath.Replace('\', '\\').Replace('"', '\"')
        $updatedUnixMilliseconds = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $telemetryPayload = "{`"pid`":$PID,`"pane_id`":`"$escapedPaneId`",`"workspace_id`":`"$escapedWorkspaceId`",`"cwd`":`"$escapedDirectoryPath`",`"updated_unix_ms`":$updatedUnixMilliseconds}"
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($script:HerdrShellTelemetryFilePath, $telemetryPayload, $utf8NoBom)
    } catch {
        Write-Verbose "Failed to publish Herdr shell telemetry for PID ${PID}: $($_.Exception.Message)"
    }
}

$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -SupportEvent -Action {
    try {
        $userHomeDirectory = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
        $telemetryFilePath = Join-Path $userHomeDirectory ".cache\herdr-shells\$PID.json"
        if ([System.IO.File]::Exists($telemetryFilePath)) {
            [System.IO.File]::Delete($telemetryFilePath)
        }
    } catch {
        Write-Verbose "Failed to remove Herdr shell telemetry on exit for PID ${PID}: $($_.Exception.Message)"
    }
}

if ($PWD -and $PWD.Provider.Name -eq 'FileSystem') {
    Publish-HerdrShellTelemetry -CurrentDirectoryPath $PWD.ProviderPath
}

if (Test-Path Function:\prompt) {
    $script:InnerPromptFunction = $function:prompt
    $script:LastEmittedKeyboardLayout = ''
    $script:KeyboardLayoutCachePath = Join-Path $HOME '.cache\wezterm-kb-layout'

    function global:prompt {
        $ansiEscape = [char]27
        $ansiBell = [char]7
        $prefixSequences = ''

        $currentLocation = $executionContext.SessionState.Path.CurrentLocation
        if ($currentLocation.Provider.Name -eq 'FileSystem') {
            $currentDirectoryPath = $currentLocation.ProviderPath
            if ($currentDirectoryPath -ne $global:LastTrackedHerdrWorkingDirectory) {
                Publish-HerdrShellTelemetry -CurrentDirectoryPath $currentDirectoryPath
            }
            $normalizedProviderPath = $currentDirectoryPath.Replace('\', '/').TrimStart('/')
            $hostName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'localhost' }
            $prefixSequences += "${ansiEscape}]7;file://${hostName}/${normalizedProviderPath}${ansiBell}"
        }

        if ([System.IO.File]::Exists($script:KeyboardLayoutCachePath)) {
            try {
                $cachedLayout = ([System.IO.File]::ReadAllText($script:KeyboardLayoutCachePath) -replace '[^A-Za-z]', '').ToUpperInvariant()
                if ($cachedLayout.Length -eq 2 -and $cachedLayout -ne $script:LastEmittedKeyboardLayout) {
                    $script:LastEmittedKeyboardLayout = $cachedLayout
                    $encodedLayout = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($cachedLayout))
                    $prefixSequences += "${ansiEscape}]1337;SetUserVar=KB=${encodedLayout}${ansiBell}"
                }
            } catch {
                Write-Verbose "Failed to read keyboard layout cache: $($_.Exception.Message)"
            }
        }

        "${prefixSequences}$(& $script:InnerPromptFunction)"
    }
}

Write-ProfileTiming -SectionName 'CachedCliInit' -StartTimestamp $sectionStart

# ── 4. PSReadLine Predictive IntelliSense, Keybindings & Tokyo Night Colors ───

$sectionStart = if ($script:IsProfileTimingEnabled) { [System.Diagnostics.Stopwatch]::GetTimestamp() } else { $null }

$psReadLineModule = Get-Module -Name PSReadLine
if (-not $psReadLineModule) {
    $psReadLineModule = Import-Module -Name PSReadLine -PassThru -ErrorAction SilentlyContinue
}
if ($PSVersionTable.PSVersion.Major -ge 7 -and $psReadLineModule -and $psReadLineModule.Version -ge [version]'2.2.0') {
    $script:IgnoredTrivialCommands = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('ls', 'cd', 'clear', 'cls', 'exit'),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $script:SecretPatterns = @('*TOKEN=*', '*PASSWORD=*', '*API_KEY=*', '*SECRET=*')

    $psReadLineOptions = @{
        EditMode                      = 'Emacs'
        BellStyle                     = 'None'
        HistoryNoDuplicates           = $true
        HistorySearchCursorMovesToEnd = $true
        MaximumHistoryCount           = 10000
        AddToHistoryHandler           = {
            param([string]$commandLine)
            if ([string]::IsNullOrWhiteSpace($commandLine) -or $commandLine.StartsWith(' ') -or $commandLine.StartsWith("`t")) {
                return $false
            }
            $trimmedCommand = $commandLine.Trim()
            if ($script:IgnoredTrivialCommands.Contains($trimmedCommand)) {
                return $false
            }
            foreach ($pattern in $script:SecretPatterns) {
                if ($trimmedCommand -like $pattern) {
                    return $false
                }
            }
            return $true
        }
        Colors                        = @{
            InlinePrediction = "`e[38;2;86;95;137m"
            Command          = "`e[38;2;122;162;247m"
            Parameter        = "`e[38;2;224;175;104m"
            String           = "`e[38;2;158;206;106m"
            Operator         = "`e[38;2;137;221;255m"
            Selection        = "`e[48;2;54;74;130m"
        }
    }
    Set-PSReadLineOption @psReadLineOptions

    try {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
    } catch {
        Write-Verbose "Skipping PSReadLine prediction view setup in non-interactive console buffer: $($_.Exception.Message)"
    }

    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key 'Shift+Tab' -Function TabCompletePrevious
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key 'Ctrl+p' -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key 'Ctrl+n' -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar
    Set-PSReadLineKeyHandler -Key 'Ctrl+f' -Function ForwardChar
    Set-PSReadLineKeyHandler -Key 'Alt+RightArrow' -Function AcceptNextSuggestionWord
    Set-PSReadLineKeyHandler -Key 'Alt+f' -Function AcceptNextSuggestionWord
    Set-PSReadLineKeyHandler -Key F2 -Function SwitchPredictionView
    Set-PSReadLineKeyHandler -Key 'Ctrl+d' -Function DeleteCharOrExit
    Set-PSReadLineKeyHandler -Key 'Alt+.' -Function YankLastArg
}

Write-ProfileTiming -SectionName 'PSReadLine' -StartTimestamp $sectionStart

# ── 5. Zero-Startup-Cost Native fzf Keybindings & CLI Argument Completers ─────

$sectionStart = if ($script:IsProfileTimingEnabled) { [System.Diagnostics.Stopwatch]::GetTimestamp() } else { $null }

$hasFd = [bool](Get-Command -Name fd -CommandType Application -ErrorAction SilentlyContinue)
if ($hasFd -and -not $env:FZF_DEFAULT_COMMAND) {
    $env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --exclude .git'
}

if (-not $env:FZF_DEFAULT_OPTS) {
    $env:FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border --color=fg:#c0caf5,bg:#1a1b26,hl:#7aa2f7,fg+:#c0caf5,bg+:#364a82,hl+:#7dcfff,info:#e0af68,prompt:#7aa2f7,pointer:#f7768e,marker:#9ece6a,spinner:#bb9af7,header:#565f89'
}

if ((Get-Command -Name fzf -CommandType Application -ErrorAction SilentlyContinue) -and (Get-Module -Name PSReadLine)) {
    Set-PSReadLineKeyHandler -Key 'Ctrl+r' -BriefDescription 'FuzzyHistorySearch' -Description 'Search command history with fzf' -ScriptBlock {
        $currentLine = $null
        $cursorIndex = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$currentLine, [ref]$cursorIndex)

        $historySavePath = (Get-PSReadLineOption).HistorySavePath
        if (-not [System.IO.File]::Exists($historySavePath)) {
            return
        }

        $allLines = [System.IO.File]::ReadAllLines($historySavePath)
        $seenCommands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $deduplicatedHistory = [System.Collections.Generic.List[string]]::new()
        for ($index = $allLines.Length - 1; $index -ge 0; $index--) {
            $entry = $allLines[$index]
            if (-not [string]::IsNullOrWhiteSpace($entry) -and $seenCommands.Add($entry)) {
                $deduplicatedHistory.Add($entry)
            }
        }

        try {
            $selectedCommand = $deduplicatedHistory | fzf --height 40% --layout=reverse --scheme=history --query="$currentLine"
            if (-not [string]::IsNullOrWhiteSpace($selectedCommand)) {
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $currentLine.Length, ($selectedCommand -join ' '))
            }
        } finally {
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
    }

    Set-PSReadLineKeyHandler -Key 'Ctrl+t' -BriefDescription 'FuzzyFileInsert' -Description 'Insert file path(s) selected with fzf' -ScriptBlock {
        try {
            $fileCandidates = if (Get-Command -Name fd -CommandType Application -ErrorAction SilentlyContinue) {
                fd --type f --hidden --exclude .git
            } else {
                Get-ChildItem -Recurse -File -Name -ErrorAction SilentlyContinue
            }

            $selectedPaths = $fileCandidates | fzf -m --height 40% --layout=reverse
            if ($selectedPaths) {
                $formattedPaths = foreach ($item in @($selectedPaths)) {
                    if ($item -match '\s') { "'$item'" } else { $item }
                }
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert(($formattedPaths -join ' '))
            }
        } finally {
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
    }

    Set-PSReadLineKeyHandler -Key 'Alt+c' -BriefDescription 'FuzzyDirectoryJump' -Description 'Change directory using fzf' -ScriptBlock {
        try {
            $directoryCandidates = if (Get-Command -Name fd -CommandType Application -ErrorAction SilentlyContinue) {
                fd --type d --hidden --exclude .git
            } else {
                Get-ChildItem -Recurse -Directory -Name -ErrorAction SilentlyContinue
            }

            $selectedDirectory = $directoryCandidates | fzf --height 40% --layout=reverse | Select-Object -First 1
            if (-not [string]::IsNullOrWhiteSpace($selectedDirectory) -and (Test-Path -LiteralPath $selectedDirectory -PathType Container)) {
                Set-Location -LiteralPath $selectedDirectory
            }
        } finally {
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
    }
}

if (Get-Command -Name winget -CommandType Application -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.UTF8Encoding]::new()
        $escapedWordToComplete = $wordToComplete.Replace('"', '""')
        $escapedCommandAst = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$escapedWordToComplete" --commandline "$escapedCommandAst" --position $cursorPosition | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

$ghCompletionPath = Resolve-CachedInitScript -Name 'gh' -CacheKey 'gh-completion' -Generator { & gh completion -s powershell }
if ($ghCompletionPath) { . $ghCompletionPath }

$carapaceCompletionPath = Resolve-CachedInitScript -Name 'carapace' -CacheKey 'carapace-completion' -Generator { & carapace _carapace powershell }
if ($carapaceCompletionPath) {
    $env:CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense'
    . $carapaceCompletionPath
}

Write-ProfileTiming -SectionName 'FzfAndCompletions' -StartTimestamp $sectionStart

# ── 6. Interactive Ergonomics (Yazi, Eza, Bat, Navigation, Utilities) ─────────

$sectionStart = if ($script:IsProfileTimingEnabled) { [System.Diagnostics.Stopwatch]::GetTimestamp() } else { $null }

function global:y {
    $tempCwdFile = [System.IO.Path]::GetTempFileName()
    try {
        yazi @args --cwd-file="$tempCwdFile"
        if ([System.IO.File]::Exists($tempCwdFile)) {
            $targetDirectory = [System.IO.File]::ReadAllText($tempCwdFile).Trim()
            if ($targetDirectory -and $targetDirectory -ne $PWD.Path -and (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
                Set-Location -LiteralPath $targetDirectory
            }
        }
    } finally {
        Remove-Item -LiteralPath $tempCwdFile -Force -ErrorAction SilentlyContinue
    }
}

if (Get-Command -Name eza -CommandType Application -ErrorAction SilentlyContinue) {
    Remove-Item -LiteralPath Alias:\ls -Force -ErrorAction SilentlyContinue
    function global:ls { eza --icons --group-directories-first @args }
    function global:ll { eza -lh --icons --git --group-directories-first @args }
    function global:la { eza -lha --icons --git --group-directories-first @args }
    function global:lt { eza --tree --level=2 --icons @args }
}

if (Get-Command -Name bat -CommandType Application -ErrorAction SilentlyContinue) {
    function global:catp { bat --paging=never @args }
}

function global:lg { lazygit @args }
function global:v { nvim @args }
function global:.. { Set-Location .. }
function global:... { Set-Location ../.. }

function global:c {
    $codesDirectory = Join-Path $HOME 'Codes'
    $dotfilesPathConfig = Join-Path $HOME '.config\dotfiles\path'
    if ([System.IO.File]::Exists($dotfilesPathConfig)) {
        foreach ($configLine in [System.IO.File]::ReadLines($dotfilesPathConfig)) {
            if ($configLine -match '^CODES_DIR="(.+)"$') {
                $configuredCodesPath = $Matches[1] -replace '^~', $HOME
                if ($IsWindows -and $configuredCodesPath -match '^/([a-zA-Z])/(.*)$') {
                    $configuredCodesPath = "$($Matches[1]):/$($Matches[2])"
                }
                if ($configuredCodesPath) {
                    $codesDirectory = $configuredCodesPath
                }
                break
            }
        }
    }
    if (Test-Path -LiteralPath $codesDirectory -PathType Container) {
        Set-Location -LiteralPath $codesDirectory
    } else {
        Write-Warning "Projects directory does not exist: $codesDirectory"
    }
}

function global:which {
    Get-Command -All @args
}

function global:touch {
    param(
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Paths
    )
    $currentUtcTime = [DateTime]::UtcNow
    foreach ($targetPath in $Paths) {
        if (Test-Path -LiteralPath $targetPath) {
            (Get-Item -LiteralPath $targetPath).LastWriteTimeUtc = $currentUtcTime
        } else {
            [void](New-Item -ItemType File -Path $targetPath -Force)
        }
    }
}

function global:mkcd {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )
    $directoryInfo = New-Item -ItemType Directory -Path $Path -Force
    Set-Location -LiteralPath $directoryInfo.FullName
}

Write-ProfileTiming -SectionName 'AliasesAndFunctions' -StartTimestamp $sectionStart

# ── 7. Per-Machine Local Overrides (~/.profile.local.ps1) ─────────────────────

$sectionStart = if ($script:IsProfileTimingEnabled) { [System.Diagnostics.Stopwatch]::GetTimestamp() } else { $null }

$localProfilePath = Join-Path $HOME '.profile.local.ps1'
if ([System.IO.File]::Exists($localProfilePath)) {
    . $localProfilePath
}

Write-ProfileTiming -SectionName 'LocalProfile' -StartTimestamp $sectionStart

if ($script:IsProfileTimingEnabled -and $script:ProfileTotalStopwatch) {
    $script:ProfileTotalStopwatch.Stop()
    $totalMs = [Math]::Round($script:ProfileTotalStopwatch.Elapsed.TotalMilliseconds, 2)
    Write-Host "[pwsh-profile] Startup completed in ${totalMs}ms" -ForegroundColor Cyan
    foreach ($entry in $script:ProfileSectionTimings) {
        Write-Host ("  - {0,-20} {1,7:F2}ms ({2})" -f $entry.Section, $entry.DurationMs, $entry.Outcome) -ForegroundColor DarkGray
    }
}
