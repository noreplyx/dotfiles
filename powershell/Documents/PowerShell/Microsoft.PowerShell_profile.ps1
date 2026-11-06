# Thin bootstrap loader for Windows PowerShell 7 ($PROFILE.CurrentUserCurrentHost)
# Forwards to the canonical XDG profile at ~/.config/powershell/Microsoft.PowerShell_profile.ps1

if ($PSVersionTable.PSVersion.Major -lt 7) {
    return
}

$xdgPowerShellProfile = Join-Path $HOME '.config\powershell\Microsoft.PowerShell_profile.ps1'
if (Test-Path -LiteralPath $xdgPowerShellProfile) {
    . $xdgPowerShellProfile
}
