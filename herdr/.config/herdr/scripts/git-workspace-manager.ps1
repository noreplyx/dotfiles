# Git Workspace Manager for Herdr (prefix+o).
# Interactive fzf overlay to list, preview, switch, push, pull, and rebase Git workspaces and worktrees.
[CmdletBinding()]
param(
    [string]$Mode = "Interactive",
    [string]$Path = "",
    [string]$WorkspaceId = "",
    [string]$WorktreeId = ""
)

$ErrorActionPreference = "Continue"
$PSNativeCommandUseErrorActionPreference = $false

trap {
    Write-Host ""
    Write-Host " [Git Workspace Manager Fatal Exception]" -ForegroundColor Red -BackgroundColor Black
    Write-Host " Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host " ScriptStackTrace: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    Write-Host ""
    if ($Mode.ToLowerInvariant() -in @("interactive", "")) {
        try {
            Read-Host "Press Enter to exit..."
        } catch {}
    }
    exit 1
}

function Write-WorkspaceLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    try {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
        if (-not $homeDir) { return }
        $cacheDir = Join-Path $homeDir ".cache"
        if (-not (Test-Path -LiteralPath $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $logPath = Join-Path $cacheDir "herdr-git-workspace.log"
        if ([System.IO.File]::Exists($logPath)) {
            $logFileInfo = [System.IO.FileInfo]::new($logPath)
            if ($logFileInfo.Length -gt 524288) {
                $rotatedLogPath = "$logPath.1"
                Remove-Item -LiteralPath $rotatedLogPath -Force -ErrorAction SilentlyContinue
                Move-Item -LiteralPath $logPath -Destination $rotatedLogPath -Force -ErrorAction SilentlyContinue
            }
        }
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $logEntry = "[$timestamp] [$Level] $Message"
        Add-Content -LiteralPath $logPath -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

Write-WorkspaceLog "Script loaded with Mode=$Mode"

function Show-FatalError {
    param(
        [string]$Message,
        [string]$Detail = ""
    )
    Write-WorkspaceLog "$Message $Detail" -Level "ERROR"
    Write-Host ""
    Write-Host " [Git Workspace Manager Error]" -ForegroundColor Red -BackgroundColor Black
    Write-Host " $Message" -ForegroundColor Red
    if ($Detail) {
        Write-Host " Details: $Detail" -ForegroundColor DarkGray
    }
    Write-Host ""
    try {
        Read-Host "Press Enter to exit..."
    } catch {}
}

function Ensure-EnvironmentPath {
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } elseif ($homeDir) { Join-Path $homeDir "AppData\Local" } else { $null }
    $programData = if ($env:ProgramData) { $env:ProgramData } else { "C:\ProgramData" }
    $programFiles = if ($env:ProgramFiles) { $env:ProgramFiles } else { "C:\Program Files" }

    $candidateDirs = [System.Collections.Generic.List[string]]::new()
    if ($homeDir) {
        $candidateDirs.Add((Join-Path $homeDir "scoop\shims"))
        $candidateDirs.Add((Join-Path $homeDir "scoop\apps\fzf\current"))
        $candidateDirs.Add((Join-Path $homeDir ".local\bin"))
        $candidateDirs.Add((Join-Path $homeDir "bin"))
        $candidateDirs.Add((Join-Path $homeDir ".cargo\bin"))
        $candidateDirs.Add((Join-Path $homeDir ".fzf\bin"))
        $candidateDirs.Add((Join-Path $homeDir ".herdr\bin"))
        $candidateDirs.Add((Join-Path $homeDir ".herdr\packages\standalone\current"))
    }
    if ($programData) {
        $candidateDirs.Add((Join-Path $programData "scoop\shims"))
        $candidateDirs.Add((Join-Path $programData "chocolatey\bin"))
    }
    if ($localAppData) {
        $candidateDirs.Add((Join-Path $localAppData "Microsoft\WinGet\Links"))
        $candidateDirs.Add((Join-Path $localAppData "Programs\fzf"))
    }
    if ($programFiles) {
        $candidateDirs.Add((Join-Path $programFiles "Git\cmd"))
        $candidateDirs.Add((Join-Path $programFiles "Git\bin"))
        $candidateDirs.Add((Join-Path $programFiles "Git\usr\bin"))
    }

    $currentPaths = $env:PATH -split [System.IO.Path]::PathSeparator
    $pathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $currentPaths) {
        if ($p) { [void]$pathSet.Add($p.TrimEnd('\', '/')) }
    }

    $pathsToAdd = [System.Collections.Generic.List[string]]::new()
    foreach ($dir in $candidateDirs) {
        if ($dir -and (Test-Path -LiteralPath $dir)) {
            $normalized = $dir.TrimEnd('\', '/')
            if (-not $pathSet.Contains($normalized)) {
                $pathsToAdd.Add($dir)
                [void]$pathSet.Add($normalized)
            }
        }
    }

    if ($pathsToAdd.Count -gt 0) {
        $env:PATH = ($pathsToAdd + $currentPaths) -join [System.IO.Path]::PathSeparator
    }
}

function Expand-UserPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }
    $trimmed = $Path.Trim()
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if ($trimmed -eq "~") {
        return $homeDir
    }
    if ($trimmed.StartsWith("~/") -or $trimmed.StartsWith("~\")) {
        $sub = $trimmed.Substring(2)
        return [System.IO.Path]::Combine($homeDir, $sub)
    }
    $expanded = [System.Environment]::ExpandEnvironmentVariables($trimmed)
    if ($expanded.StartsWith("~/") -or $expanded.StartsWith("~\")) {
        $sub = $expanded.Substring(2)
        return [System.IO.Path]::Combine($homeDir, $sub)
    }
    return $expanded
}

function Normalize-DirPath {
    param([string]$Path)
    $expanded = Expand-UserPath -Path $Path
    if (-not (Test-Path -LiteralPath $expanded)) {
        return $expanded
    }
    try {
        $resolved = (Resolve-Path -LiteralPath $expanded -ErrorAction SilentlyContinue).Path
        if ($resolved) {
            return $resolved
        }
    } catch {}
    return [System.IO.Path]::GetFullPath($expanded)
}

function Test-GitRepository {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    $expanded = Expand-UserPath -Path $Path
    if (-not (Test-Path -LiteralPath $expanded)) {
        return $false
    }
    $gitMeta = Join-Path $expanded ".git"
    if (Test-Path -LiteralPath $gitMeta) {
        return $true
    }
    try {
        & git -C $expanded rev-parse --git-dir 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

$script:CachedHerdrBinary = $null
$script:HerdrBinaryChecked = $false

function Resolve-HerdrBinary {
    if ($script:HerdrBinaryChecked) {
        return $script:CachedHerdrBinary
    }
    $resolved = $null
    if ($env:HERDR_BIN_PATH -and (Test-Path -LiteralPath $env:HERDR_BIN_PATH)) {
        $resolved = $env:HERDR_BIN_PATH
    } else {
        $herdrExeCommand = Get-Command herdr.exe -ErrorAction SilentlyContinue
        if ($herdrExeCommand -and $herdrExeCommand.Source) {
            $resolved = $herdrExeCommand.Source
        } elseif (($herdrCommand = Get-Command herdr -ErrorAction SilentlyContinue) -and $herdrCommand.Source) {
            $resolved = $herdrCommand.Source
        } else {
            $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
            if ($homeDir) {
                $standalonePath = Join-Path $homeDir ".herdr\packages\standalone\current\herdr.exe"
                $standaloneUnix = Join-Path $homeDir ".herdr/packages/standalone/current/herdr"
                $binPath = Join-Path $homeDir ".herdr\bin\herdr.exe"
                $binUnix = Join-Path $homeDir ".herdr/bin/herdr"
                if (Test-Path -LiteralPath $standalonePath) {
                    $resolved = $standalonePath
                } elseif (Test-Path -LiteralPath $standaloneUnix) {
                    $resolved = $standaloneUnix
                } elseif (Test-Path -LiteralPath $binPath) {
                    $resolved = $binPath
                } elseif (Test-Path -LiteralPath $binUnix) {
                    $resolved = $binUnix
                }
            }
        }
    }
    $script:CachedHerdrBinary = $resolved
    $script:HerdrBinaryChecked = $true
    return $script:CachedHerdrBinary
}

function Resolve-FzfBinary {
    $fzfExe = Get-Command fzf.exe -ErrorAction SilentlyContinue
    if ($fzfExe -and $fzfExe.Source) {
        return $fzfExe.Source
    }
    $fzfCmd = Get-Command fzf -ErrorAction SilentlyContinue
    if ($fzfCmd -and $fzfCmd.Source) {
        return $fzfCmd.Source
    }

    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } elseif ($homeDir) { Join-Path $homeDir "AppData\Local" } else { $null }
    $programData = if ($env:ProgramData) { $env:ProgramData } else { "C:\ProgramData" }

    $directChecks = [System.Collections.Generic.List[string]]::new()
    if ($homeDir) {
        $directChecks.Add((Join-Path $homeDir "scoop\shims\fzf.exe"))
        $directChecks.Add((Join-Path $homeDir "scoop\apps\fzf\current\fzf.exe"))
    }
    if ($programData) {
        $directChecks.Add((Join-Path $programData "chocolatey\bin\fzf.exe"))
    }
    if ($localAppData) {
        $directChecks.Add((Join-Path $localAppData "Microsoft\WinGet\Links\fzf.exe"))
        $directChecks.Add((Join-Path $localAppData "Programs\fzf\fzf.exe"))
    }
    if ($homeDir) {
        $directChecks.Add((Join-Path $homeDir ".fzf\bin\fzf.exe"))
        $directChecks.Add((Join-Path $homeDir ".local\bin\fzf.exe"))
        $directChecks.Add((Join-Path $homeDir "bin\fzf.exe"))
    }

    foreach ($path in $directChecks) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }
    return $null
}

function Send-HerdrNotification {
    param(
        [string]$Title,
        [string]$Body,
        [string]$Sound = "none"
    )
    $herdrBinaryPath = Resolve-HerdrBinary
    if ($herdrBinaryPath) {
        try {
            & $herdrBinaryPath notification show $Title --body $Body --position top-right --sound $Sound 2>$null | Out-Null
        } catch {}
    }
}

function Extract-JsonItems {
    param(
        $ParsedJson,
        [string]$ItemType
    )
    if (-not $ParsedJson) {
        return @()
    }
    if ($ParsedJson -is [System.Collections.IEnumerable] -and -not ($ParsedJson -is [PSCustomObject]) -and -not ($ParsedJson -is [string])) {
        return @($ParsedJson)
    }
    if ($ParsedJson -is [PSCustomObject]) {
        if ($ParsedJson.PSObject.Properties['result'] -and $ParsedJson.result) {
            $ResultNode = $ParsedJson.result
            if ($ResultNode -is [System.Collections.IEnumerable] -and -not ($ResultNode -is [PSCustomObject]) -and -not ($ResultNode -is [string])) {
                return @($ResultNode)
            }
            if ($ResultNode -is [PSCustomObject]) {
                if ($ResultNode.PSObject.Properties[$ItemType] -and $ResultNode.$ItemType) {
                    return @($ResultNode.$ItemType)
                }
                if ($ResultNode.PSObject.Properties['data'] -and $ResultNode.data) {
                    return @($ResultNode.data)
                }
                if ($ResultNode.PSObject.Properties['items'] -and $ResultNode.items) {
                    return @($ResultNode.items)
                }
                if ($ResultNode.PSObject.Properties['id']) {
                    return @($ResultNode)
                }
            }
        }
        if ($ParsedJson.PSObject.Properties[$ItemType] -and $ParsedJson.$ItemType) {
            return @($ParsedJson.$ItemType)
        }
        if ($ParsedJson.PSObject.Properties['data'] -and $ParsedJson.data) {
            return @($ParsedJson.data)
        }
        if ($ParsedJson.PSObject.Properties['items'] -and $ParsedJson.items) {
            return @($ParsedJson.items)
        }
        if ($ParsedJson.PSObject.Properties['id']) {
            return @($ParsedJson)
        }
    }
    return @()
}

function Get-ObjectPath {
    param($InputObject)
    if (-not $InputObject -or -not ($InputObject -is [PSCustomObject])) {
        return ""
    }
    $candidates = @('cwd', 'path', 'directory', 'root', 'folder', 'location', 'workdir', 'working_directory', 'workingDirectory')
    foreach ($prop in $candidates) {
        if ($InputObject.PSObject.Properties[$prop] -and $InputObject.$prop) {
            return [string]$InputObject.$prop
        }
    }
    return ""
}

function Get-ObjectId {
    param($InputObject)
    if (-not $InputObject -or -not ($InputObject -is [PSCustomObject])) {
        return ""
    }
    $candidates = @('id', 'workspace_id', 'workspaceId', 'workspace', 'uuid')
    foreach ($prop in $candidates) {
        if ($InputObject.PSObject.Properties[$prop] -and $InputObject.$prop) {
            return [string]$InputObject.$prop
        }
    }
    return ""
}

function Get-ObjectName {
    param($InputObject, [string]$DefaultValue = "")
    if (-not $InputObject -or -not ($InputObject -is [PSCustomObject])) {
        return $DefaultValue
    }
    $candidates = @('name', 'title', 'label')
    foreach ($prop in $candidates) {
        if ($InputObject.PSObject.Properties[$prop] -and $InputObject.$prop) {
            return [string]$InputObject.$prop
        }
    }
    return $DefaultValue
}

function Get-GitBaseBranch {
    param([string]$Path)
    $candidates = @("origin/main", "origin/master", "main", "master")
    foreach ($candidate in $candidates) {
        & git -C $Path rev-parse --verify --quiet $candidate 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return $candidate
        }
    }
    return $null
}

function Format-WorktreeEntry {
    param(
        [string]$WorkspaceName,
        [string]$WorkspaceId,
        [string]$WorktreeId,
        [string]$WorktreePath
    )
    if ([string]::IsNullOrWhiteSpace($WorktreePath)) {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($WorkspaceName)) {
        $WorkspaceName = "default"
    }
    if ([string]::IsNullOrWhiteSpace($WorkspaceId)) {
        $WorkspaceId = "-"
    }
    if ([string]::IsNullOrWhiteSpace($WorktreeId)) {
        $WorktreeId = "-"
    }
    $expanded = Expand-UserPath -Path $WorktreePath
    if (-not (Test-Path -LiteralPath $expanded)) {
        return $null
    }

    $statusLines = & git -C $expanded status --porcelain=v2 --branch --ignore-submodules=all -unormal 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $statusLines) {
        return $null
    }

    $rawBranch = ""
    $oid = ""
    $hasUpstream = $false
    $ahead = 0
    $behind = 0
    $isDirty = $false

    foreach ($line in $statusLines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^#\s+branch\.head\s+(.+)$') {
            $rawBranch = $Matches[1]
        } elseif ($trimmed -match '^#\s+branch\.oid\s+(.+)$') {
            $oid = $Matches[1]
        } elseif ($trimmed -match '^#\s+branch\.ab\s+\+(\d+)\s+-(\d+)$') {
            $hasUpstream = $true
            $ahead = [int]$Matches[1]
            $behind = [int]$Matches[2]
        } elseif ($trimmed -and -not $trimmed.StartsWith("#")) {
            $isDirty = $true
        }
    }

    $isDetachedOrInitial = $false
    $branch = $rawBranch
    if (-not $rawBranch -or $rawBranch -eq "(detached)" -or $oid -eq "(initial)") {
        $isDetachedOrInitial = $true
        if ($oid -and $oid -ne "(initial)") {
            $branch = if ($oid.Length -gt 7) { $oid.Substring(0, 7) } else { $oid }
        } else {
            $branch = "unknown"
        }
    }

    $commitsToPush = 0
    $commitsToPull = 0
    $commitsBehindBase = 0

    if (-not $isDetachedOrInitial) {
        $baseBranch = Get-GitBaseBranch -Path $expanded
        $baseName = if ($baseBranch -and $baseBranch -match '^origin/(.+)$') { $Matches[1] } else { $baseBranch }
        $isOnBaseBranch = ($baseBranch -and ($branch -eq $baseName -or $branch -eq $baseBranch))

        $leftCount = 0
        $rightCount = 0
        if ($baseBranch -and ((-not $hasUpstream) -or (-not $isOnBaseBranch))) {
            $lrOut = (& git -C $expanded rev-list --left-right --count "$baseBranch...HEAD" 2>$null)
            if ($lrOut) {
                $parts = -split ([string]$lrOut).Trim()
                if ($parts.Count -ge 2) {
                    [void][int]::TryParse($parts[0], [ref]$leftCount)
                    [void][int]::TryParse($parts[1], [ref]$rightCount)
                }
            }
        }

        if ($hasUpstream) {
            $commitsToPush = $ahead
            $commitsToPull = $behind
        } else {
            $commitsToPull = 0
            $commitsToPush = $rightCount
        }

        if ($isOnBaseBranch -or -not $baseBranch) {
            $commitsBehindBase = 0
        } else {
            $commitsBehindBase = $leftCount
        }
    }

    $dirtyStr = if ($isDirty) { " *" } else { "" }

    $worktreeDir = Split-Path -Leaf $expanded
    if (-not $worktreeDir) {
        $worktreeDir = $expanded
    }

    $wsPrefix = if ($WorkspaceName -and $WorkspaceName -ne "default" -and $WorkspaceName -ne "-") { "[$WorkspaceName]  " } else { "" }
    return "$wsPrefix$worktreeDir  ($branch)  [push:$commitsToPush | pull:$commitsToPull | rebase:$commitsBehindBase]$dirtyStr`t$WorkspaceId`t$WorktreeId`t$expanded"
}

function Invoke-ListMode {
    Ensure-EnvironmentPath
    $herdr = Resolve-HerdrBinary
    $outputLines = [System.Collections.Generic.List[string]]::new()
    $candidateList = [System.Collections.Generic.List[hashtable]]::new()
    $candidateIndexByNormPath = @{}
    $wsMap = @{}

    $herdrDisplayName = if ($herdr) { $herdr } else { "none" }
    Write-WorkspaceLog "Listing git workspaces and worktrees (Herdr: $herdrDisplayName)" -Level "INFO"

    if ($herdr) {
        $wsJson = $null
        $wtJson = $null
        try {
            $wsJson = & $herdr workspace list --json 2>$null
        } catch {
            Write-WorkspaceLog "Error querying workspace list --json: $($_.Exception.Message)" -Level "WARN"
        }
        try {
            $wtJson = & $herdr worktree list --json 2>$null
        } catch {
            Write-WorkspaceLog "Error querying worktree list --json: $($_.Exception.Message)" -Level "WARN"
        }

        # 1. Parse Workspaces JSON
        if ($wsJson) {
            try {
                $wsObj = ($wsJson -join "`n") | ConvertFrom-Json
                $workspaces = Extract-JsonItems -ParsedJson $wsObj -ItemType "workspaces"
                Write-WorkspaceLog "Extracted $($workspaces.Count) workspaces from JSON" -Level "INFO"

                foreach ($workspaceItem in $workspaces) {
                    $wsId = Get-ObjectId -InputObject $workspaceItem
                    $defaultWsName = if ($wsId) { $wsId } else { "default" }
                    $wsName = Get-ObjectName -InputObject $workspaceItem -DefaultValue $defaultWsName
                    if ($wsId) {
                        $wsMap[$wsId] = $wsName
                    }
                    $wsPath = Get-ObjectPath -InputObject $workspaceItem
                    if ($wsPath) {
                        $resolvedPath = Normalize-DirPath -Path $wsPath
                        if (Test-GitRepository -Path $resolvedPath) {
                            $normalizedPathKey = $resolvedPath.ToLowerInvariant()
                            if (-not $candidateIndexByNormPath.ContainsKey($normalizedPathKey)) {
                                $candidateIndexByNormPath[$normalizedPathKey] = $candidateList.Count
                                $candidateList.Add(@{
                                    WorkspaceName = $wsName
                                    WorkspaceId   = if ($wsId) { $wsId } else { "-" }
                                    WorktreeId    = "-"
                                    Path          = $resolvedPath
                                })
                            }
                        }
                    }
                }
            } catch {
                Write-WorkspaceLog "Failed parsing workspaces JSON: $($_.Exception.Message)" -Level "WARN"
            }
        }

        # 2. Parse Worktrees JSON
        if ($wtJson) {
            try {
                $wtObj = ($wtJson -join "`n") | ConvertFrom-Json
                $worktrees = Extract-JsonItems -ParsedJson $wtObj -ItemType "worktrees"
                Write-WorkspaceLog "Extracted $($worktrees.Count) worktrees from JSON" -Level "INFO"

                foreach ($worktreeItem in $worktrees) {
                    $wtPath = Get-ObjectPath -InputObject $worktreeItem
                    if ($wtPath) {
                        $resolvedPath = Normalize-DirPath -Path $wtPath
                        if (Test-GitRepository -Path $resolvedPath) {
                            $normalizedPathKey = $resolvedPath.ToLowerInvariant()
                            $wsId = if ($worktreeItem.PSObject.Properties['workspace_id'] -and $worktreeItem.workspace_id) { [string]$worktreeItem.workspace_id } elseif ($worktreeItem.PSObject.Properties['workspaceId'] -and $worktreeItem.workspaceId) { [string]$worktreeItem.workspaceId } elseif ($worktreeItem.PSObject.Properties['workspace'] -and $worktreeItem.workspace) { [string]$worktreeItem.workspace } else { "" }
                            $wtId = if ($worktreeItem.PSObject.Properties['id'] -and $worktreeItem.id) { [string]$worktreeItem.id } elseif ($worktreeItem.PSObject.Properties['worktree_id'] -and $worktreeItem.worktree_id) { [string]$worktreeItem.worktree_id } elseif ($worktreeItem.PSObject.Properties['worktreeId'] -and $worktreeItem.worktreeId) { [string]$worktreeItem.worktreeId } else { "" }
                            $wsName = if ($wsId -and $wsMap.ContainsKey($wsId)) { $wsMap[$wsId] } elseif ($wsId) { $wsId } else { "default" }

                            if ($candidateIndexByNormPath.ContainsKey($normalizedPathKey)) {
                                $idx = $candidateIndexByNormPath[$normalizedPathKey]
                                if ($wtId) {
                                    $candidateList[$idx].WorktreeId = $wtId
                                }
                                if (($candidateList[$idx].WorkspaceId -eq "-" -or -not $candidateList[$idx].WorkspaceId) -and $wsId) {
                                    $candidateList[$idx].WorkspaceId = $wsId
                                }
                            } else {
                                $candidateIndexByNormPath[$normalizedPathKey] = $candidateList.Count
                                $candidateList.Add(@{
                                    WorkspaceName = $wsName
                                    WorkspaceId   = if ($wsId) { $wsId } else { "-" }
                                    WorktreeId    = if ($wtId) { $wtId } else { "-" }
                                    Path          = $resolvedPath
                                })
                            }
                        }
                    }
                }
            } catch {
                Write-WorkspaceLog "Failed parsing worktrees JSON: $($_.Exception.Message)" -Level "WARN"
            }
        }

        # 3. Plain text fallback if JSON yielded 0 candidates
        if ($candidateList.Count -eq 0) {
            Write-WorkspaceLog "JSON parsing yielded 0 candidates; running plain-text CLI fallback" -Level "INFO"
            try {
                $wsText = & $herdr workspace list 2>$null
                $wtText = & $herdr worktree list 2>$null

                $wsNameById = @{}
                if ($wsText) {
                    foreach ($line in ($wsText -split "`r?`n")) {
                        $trimmed = $line.Trim()
                        if (-not $trimmed -or $trimmed -match '^(ID\s+|---+)') { continue }
                        $cols = -split $trimmed
                        if ($cols.Count -ge 2) {
                            $wsNameById[$cols[0]] = $cols[1]
                        } elseif ($cols.Count -eq 1) {
                            $wsNameById[$cols[0]] = $cols[0]
                        }
                        if ($cols.Count -ge 3) {
                            $potentialPath = $cols[2..($cols.Count - 1)] -join " "
                            $resolvedPath = Normalize-DirPath -Path $potentialPath
                            if (Test-GitRepository -Path $resolvedPath) {
                                $normalizedPathKey = $resolvedPath.ToLowerInvariant()
                                if (-not $candidateIndexByNormPath.ContainsKey($normalizedPathKey)) {
                                    $candidateIndexByNormPath[$normalizedPathKey] = $candidateList.Count
                                    $candidateList.Add(@{
                                        WorkspaceName = $cols[1]
                                        WorkspaceId   = if ($cols[0]) { $cols[0] } else { "-" }
                                        WorktreeId    = "-"
                                        Path          = $resolvedPath
                                    })
                                }
                            }
                        }
                    }
                }

                if ($wtText) {
                    foreach ($line in ($wtText -split "`r?`n")) {
                        $trimmed = $line.Trim()
                        if (-not $trimmed -or $trimmed -match '^(ID\s+|---+)') { continue }
                        $cols = -split $trimmed
                        if ($cols.Count -ge 3) {
                            $wtId = $cols[0]
                            $wsId = $cols[1]
                            $wtPath = $cols[2..($cols.Count - 1)] -join " "
                            $resolvedPath = Normalize-DirPath -Path $wtPath
                            if (Test-GitRepository -Path $resolvedPath) {
                                $normalizedPathKey = $resolvedPath.ToLowerInvariant()
                                $wsName = if ($wsNameById.ContainsKey($wsId)) { $wsNameById[$wsId] } elseif ($wsId) { $wsId } else { "default" }
                                if ($candidateIndexByNormPath.ContainsKey($normalizedPathKey)) {
                                    $idx = $candidateIndexByNormPath[$normalizedPathKey]
                                    if ($wtId) {
                                        $candidateList[$idx].WorktreeId = $wtId
                                    }
                                    if (($candidateList[$idx].WorkspaceId -eq "-" -or -not $candidateList[$idx].WorkspaceId) -and $wsId) {
                                        $candidateList[$idx].WorkspaceId = $wsId
                                    }
                                } else {
                                    $candidateIndexByNormPath[$normalizedPathKey] = $candidateList.Count
                                    $candidateList.Add(@{
                                        WorkspaceName = $wsName
                                        WorkspaceId   = if ($wsId) { $wsId } else { "-" }
                                        WorktreeId    = if ($wtId) { $wtId } else { "-" }
                                        Path          = $resolvedPath
                                    })
                                }
                            }
                        }
                    }
                }
            } catch {
                Write-WorkspaceLog "Plain-text fallback failed: $($_.Exception.Message)" -Level "WARN"
            }
        }
    }

    # Format all candidates
    foreach ($candidate in $candidateList) {
        $formatted = Format-WorktreeEntry -WorkspaceName $candidate.WorkspaceName -WorkspaceId $candidate.WorkspaceId -WorktreeId $candidate.WorktreeId -WorktreePath $candidate.Path
        if ($formatted) {
            $outputLines.Add($formatted)
        }
    }

    # Fallback to current git repo if 0 entries
    if ($outputLines.Count -eq 0) {
        try {
            $repoRoot = (& git rev-parse --show-toplevel 2>$null)
            if ($repoRoot) {
                $expandedRoot = Normalize-DirPath -Path $repoRoot
                $formattedRoot = Format-WorktreeEntry -WorkspaceName "default" -WorkspaceId "default" -WorktreeId "-" -WorktreePath $expandedRoot
                if ($formattedRoot) {
                    $outputLines.Add($formattedRoot)
                }
            }
        } catch {}
    }

    # Final fallback: placeholder line if 0 entries found
    if ($outputLines.Count -eq 0) {
        Write-WorkspaceLog "No git workspaces or worktrees found; outputting placeholder" -Level "WARN"
        $outputLines.Add("[No Git Workspaces Found]  No active git repositories found in Herdr workspaces`t-`t-`t-")
    }

    foreach ($line in $outputLines) {
        Write-Output $line
    }
}

function Invoke-PreviewMode {
    param(
        [string]$TargetPath,
        [string]$WorkspaceId = ""
    )
    if ($WorkspaceId -eq "-" -or [string]::IsNullOrWhiteSpace($TargetPath) -or $TargetPath -eq "-") {
        Write-Output "No active git repositories found in Herdr workspaces."
        Write-Output "Open a project with a Git repository in Herdr or create a worktree."
        return
    }
    $expanded = Expand-UserPath -Path $TargetPath
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $previewScript = Join-Path $scriptDir "git-workspace-manager-preview.cmd"
    if (Test-Path -LiteralPath $previewScript) {
        & $previewScript $expanded $WorkspaceId
        return
    }
    if (-not (Test-Path -LiteralPath $expanded)) {
        Write-Output "Directory not found: $TargetPath"
        return
    }
    & git -C $expanded rev-parse --git-dir 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Not a git repository: $TargetPath"
        return
    }
    & git -C $expanded log -1 --format="Commit: %h | Date: %cd (%cr) | Author: %an" 2>$null
    Write-Output ""
    & git -C $expanded status -s --ignore-submodules=all
    Write-Output ""
    & git -C $expanded log -n 6 --graph --format="%C(auto)%h%d %s %C(cyan)(%cr)%C(reset)" --color=always
}

function Invoke-GitNonInteractive {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )
    $prevTerminalPrompt = $env:GIT_TERMINAL_PROMPT
    $prevGcmInteractive = $env:GCM_INTERACTIVE
    $prevGitEditor = $env:GIT_EDITOR
    try {
        $env:GIT_TERMINAL_PROMPT = "0"
        $env:GCM_INTERACTIVE = "never"
        $env:GIT_EDITOR = "true"
        & git -c core.editor=true @Arguments
        return $LASTEXITCODE
    } finally {
        $env:GIT_TERMINAL_PROMPT = $prevTerminalPrompt
        $env:GCM_INTERACTIVE = $prevGcmInteractive
        $env:GIT_EDITOR = $prevGitEditor
    }
}

function Assert-ValidGitWorktreeBranch {
    param(
        [string]$TargetPath,
        [string]$WorkspaceId = "",
        [Parameter(Mandatory = $true)][string]$ActionLabel,
        [switch]$RequireCleanTree
    )
    if ($WorkspaceId -eq "-" -or [string]::IsNullOrWhiteSpace($TargetPath) -or $TargetPath -eq "-") {
        return @{ IsNoOp = $true; ResolvedPath = ""; RepoName = ""; CurrentBranch = "" }
    }
    $expanded = Expand-UserPath -Path $TargetPath
    if (-not (Test-Path -LiteralPath $expanded)) {
        Send-HerdrNotification -Title "Git $ActionLabel Failed" -Body "Invalid directory: $TargetPath"
        exit 1
    }
    if (-not (Test-GitRepository -Path $expanded)) {
        Send-HerdrNotification -Title "Git $ActionLabel Failed" -Body "Not a git repository: $TargetPath"
        exit 1
    }
    $resolved = Normalize-DirPath -Path $expanded
    $repoName = Split-Path -Leaf $resolved
    $currentBranch = (& git -C $resolved branch --show-current 2>$null)
    if (-not $currentBranch) {
        Send-HerdrNotification -Title "Git $ActionLabel Failed" -Body "Detached HEAD in $repoName"
        exit 1
    }
    if ($RequireCleanTree) {
        $dirty = (& git -C $resolved status --porcelain 2>$null)
        if ($dirty) {
            Send-HerdrNotification -Title "Git $ActionLabel Aborted" -Body "Working tree is dirty in $repoName"
            exit 1
        }
    }
    return @{
        IsNoOp        = $false
        ResolvedPath  = $resolved
        RepoName      = $repoName
        CurrentBranch = [string]$currentBranch
    }
}

function Invoke-PushMode {
    param(
        [string]$TargetPath,
        [string]$WorkspaceId = ""
    )
    $validation = Assert-ValidGitWorktreeBranch -TargetPath $TargetPath -WorkspaceId $WorkspaceId -ActionLabel "Push"
    if ($validation.IsNoOp) { return }
    $resolved = $validation.ResolvedPath
    $repoName = $validation.RepoName
    $currentBranch = $validation.CurrentBranch

    Send-HerdrNotification -Title "Git Push" -Body "Pushing $currentBranch in $repoName..."

    & git -C $resolved rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $exitCode = Invoke-GitNonInteractive -C $resolved push -u origin $currentBranch
    } else {
        $exitCode = Invoke-GitNonInteractive -C $resolved push
    }

    if ($exitCode -eq 0) {
        Send-HerdrNotification -Title "Git Push" -Body "Pushed $currentBranch successfully in $repoName"
    } else {
        Send-HerdrNotification -Title "Git Push Failed" -Body "Failed to push $currentBranch in $repoName"
        exit 1
    }
}

function Invoke-PullMode {
    param(
        [string]$TargetPath,
        [string]$WorkspaceId = ""
    )
    $validation = Assert-ValidGitWorktreeBranch -TargetPath $TargetPath -WorkspaceId $WorkspaceId -ActionLabel "Pull" -RequireCleanTree
    if ($validation.IsNoOp) { return }
    $resolved = $validation.ResolvedPath
    $repoName = $validation.RepoName
    $currentBranch = $validation.CurrentBranch

    Send-HerdrNotification -Title "Git Pull" -Body "Pulling $currentBranch in $repoName..."

    $exitCode = Invoke-GitNonInteractive -C $resolved pull --ff-only
    if ($exitCode -eq 0) {
        Send-HerdrNotification -Title "Git Pull" -Body "Pulled successfully in $repoName"
    } else {
        Send-HerdrNotification -Title "Git Pull Failed" -Body "Failed to pull in $repoName"
        exit 1
    }
}

function Invoke-RebaseMode {
    param(
        [string]$TargetPath,
        [string]$WorkspaceId = ""
    )
    $validation = Assert-ValidGitWorktreeBranch -TargetPath $TargetPath -WorkspaceId $WorkspaceId -ActionLabel "Rebase" -RequireCleanTree
    if ($validation.IsNoOp) { return }
    $resolved = $validation.ResolvedPath
    $repoName = $validation.RepoName
    $currentBranch = $validation.CurrentBranch

    $baseBranch = Get-GitBaseBranch -Path $resolved
    $baseName = if ($baseBranch -and $baseBranch -match '^origin/(.+)$') { $Matches[1] } else { $baseBranch }
    $target = $null

    if ($baseBranch -and $currentBranch -ne $baseName -and $currentBranch -ne $baseBranch) {
        $target = $baseBranch
    } else {
        & git -C $resolved rev-parse --verify --quiet "@{u}" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $target = "@{u}"
        } elseif ($baseBranch) {
            $target = $baseBranch
        }
    }

    if (-not $target) {
        Send-HerdrNotification -Title "Git Rebase Failed" -Body "No suitable base or upstream branch found in $repoName"
        exit 1
    }

    Send-HerdrNotification -Title "Git Rebase" -Body "Rebasing $currentBranch in $repoName..."

    $exitCode = Invoke-GitNonInteractive -C $resolved rebase $target
    if ($exitCode -eq 0) {
        Send-HerdrNotification -Title "Git Rebase" -Body "Rebased onto $target in $repoName"
    } else {
        & git -C $resolved rebase --abort 2>$null | Out-Null
        Send-HerdrNotification -Title "Git Rebase Failed" -Body "Rebase onto $target failed; aborted in $repoName"
        exit 1
    }
}

function Invoke-InteractiveMode {
    try {
        Ensure-EnvironmentPath
        Write-WorkspaceLog "Starting interactive mode" -Level "INFO"

        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Show-FatalError -Message "git is required for interactive mode but was not found in PATH." -Detail "Please install Git or ensure it is available in PATH."
            exit 1
        }

        $fzfBinary = Resolve-FzfBinary
        if (-not $fzfBinary) {
            Show-FatalError -Message "fzf is required for interactive mode but was not found in PATH." -Detail "Please install fzf (e.g. scoop install fzf, choco install fzf, or winget install fzf)."
            exit 1
        }

        $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
        $psExe = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
            "pwsh.exe"
        } elseif (Get-Command pwsh -ErrorAction SilentlyContinue) {
            "pwsh"
        } elseif (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
            "powershell.exe"
        } else {
            "powershell"
        }

        $normalizedScriptPath = ($scriptPath -replace '\\', '/')
        $header = "[Enter] Switch Worktree | [Alt-p] Push | [Alt-u] Pull | [Alt-r] Rebase | [Ctrl-r] Refresh | [Esc] Close"
        function Get-ActionCommand {
            param([string]$Action)
            return $psExe + ' -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $normalizedScriptPath + '" -Mode ' + $Action + ' -Path {4} -WorkspaceId {2} >nul 2>&1'
        }

        $previewScript = Join-Path (Split-Path -Parent $scriptPath) "git-workspace-manager-preview.cmd"
        $previewCmd = "`"$previewScript`" {4} {2}"
        $pushCmd = Get-ActionCommand "Push"
        $pullCmd = Get-ActionCommand "Pull"
        $rebaseCmd = Get-ActionCommand "Rebase"
        $listCmd = $psExe + ' -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $normalizedScriptPath + '" -Mode List'

        $items = @(Invoke-ListMode)
        Write-WorkspaceLog "Invoke-ListMode yielded $($items.Count) line(s)" -Level "INFO"

        if ($items.Count -eq 0) {
            $items = @("[No Git Workspaces Found]  No active git repositories found in Herdr workspaces`t-`t-`t-")
        }

        $selected = $null
        $previousShellEnv = $env:SHELL
        try {
            $env:SHELL = $null
            $selected = $items | & $fzfBinary `
                --delimiter="`t" `
                --with-nth=1 `
                --header="$header" `
                --preview="$previewCmd" `
                --preview-window=right:55%:wrap `
                --bind "alt-p:execute-silent($pushCmd)+reload($listCmd)" `
                --bind "alt-u:execute-silent($pullCmd)+reload($listCmd)" `
                --bind "alt-r:execute-silent($rebaseCmd)+reload($listCmd)" `
                --bind "ctrl-r:reload($listCmd)"
        } catch {
            Show-FatalError -Message "Failed while executing fzf interface." -Detail $_.Exception.Message
            exit 1
        } finally {
            $env:SHELL = $previousShellEnv
        }

        if ($LASTEXITCODE -gt 1 -and $LASTEXITCODE -ne 130) {
            Show-FatalError -Message "fzf exited with error code $LASTEXITCODE."
            exit 1
        }

        if (-not $selected) {
            Write-WorkspaceLog "No item selected; exiting" -Level "INFO"
            exit 0
        }

        $parts = $selected -split "`t"
        $wsId = if ($parts.Count -ge 2) { $parts[1] } else { "" }
        $wtId = if ($parts.Count -ge 3) { $parts[2] } else { "" }

        if ($wsId -eq "-" -or $selected.StartsWith("[No Git Workspaces Found]")) {
            Write-WorkspaceLog "Placeholder item selected; exiting without action" -Level "INFO"
            exit 0
        }

        Write-WorkspaceLog "Selected item: wsId='$wsId', wtId='$wtId'" -Level "INFO"
        $herdr = Resolve-HerdrBinary
        if ($herdr) {
            if ($wsId -and $wsId -ne "default" -and $wsId -ne "-") {
                try { & $herdr workspace focus $wsId 2>$null | Out-Null } catch {}
            }
            if ($wtId -and $wtId -ne "default" -and $wtId -ne "-") {
                try { & $herdr worktree focus $wtId 2>$null | Out-Null } catch {}
            }
        }
    } catch {
        Show-FatalError -Message "Unexpected error in interactive mode: $($_.Exception.Message)" -Detail $_.ScriptStackTrace
        exit 1
    }
}

if ($Mode.StartsWith("--")) {
    $Mode = $Mode.Substring(2)
} elseif ($Mode.StartsWith("-")) {
    $Mode = $Mode.Substring(1)
}

try {
    switch ($Mode.ToLowerInvariant()) {
        "list" {
            Invoke-ListMode
        }
        "preview" {
            Invoke-PreviewMode -TargetPath $Path -WorkspaceId $WorkspaceId
        }
        "push" {
            Invoke-PushMode -TargetPath $Path -WorkspaceId $WorkspaceId
        }
        "pull" {
            Invoke-PullMode -TargetPath $Path -WorkspaceId $WorkspaceId
        }
        "rebase" {
            Invoke-RebaseMode -TargetPath $Path -WorkspaceId $WorkspaceId
        }
        "interactive" {
            Invoke-InteractiveMode
        }
        default {
            Invoke-InteractiveMode
        }
    }
} catch {
    if ($Mode.ToLowerInvariant() -in @("interactive", "")) {
        Show-FatalError -Message "Fatal error: $($_.Exception.Message)" -Detail $_.ScriptStackTrace
        exit 1
    } else {
        Write-WorkspaceLog "Fatal error in mode '$Mode': $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}
