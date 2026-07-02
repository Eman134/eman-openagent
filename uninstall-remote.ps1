#Requires -Version 5.1
<#
.SYNOPSIS
    Remote uninstaller for eman-openagent - for installs done via
    install-remote.ps1 (no local git clone to run uninstall.ps1 from).

.DESCRIPTION
    Runs the bundled uninstall.ps1 from the install location
    (%LOCALAPPDATA%\Programs\eman-openagent) to remove the context menu
    entries, then deletes that folder.

.EXAMPLE
    irm https://raw.githubusercontent.com/Eman134/eman-openagent/main/uninstall-remote.ps1 | iex
#>

$ErrorActionPreference = 'Stop'

$installDir = Join-Path $env:LOCALAPPDATA 'Programs\eman-openagent'
$uninstallScript = Join-Path $installDir 'uninstall.ps1'

if (Test-Path -LiteralPath $uninstallScript) {
    & $uninstallScript
}
else {
    Write-Host "No install found at $installDir (nothing to remove from the context menu)." -ForegroundColor Yellow
}

if (Test-Path -LiteralPath $installDir) {
    Remove-Item -LiteralPath $installDir -Recurse -Force
    Write-Host "Removed $installDir" -ForegroundColor Green
}
