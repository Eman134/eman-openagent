#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the "Open Agent" item in the Explorer context menu
    (right-click on a folder, and right-click on empty space inside a folder).

.DESCRIPTION
    Registers the entries under HKEY_CURRENT_USER (no admin required)
    and copies the default agents config to
    %LOCALAPPDATA%\eman-openagent\agents.json, where it can be freely
    edited without affecting the repository.
#>

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$quickScriptPath = Join-Path $repoRoot 'scripts\Run-Agent.ps1'
$defaultConfigPath = Join-Path $repoRoot 'config\agents.json'

if (-not (Test-Path -LiteralPath $quickScriptPath)) {
    throw "Could not find $quickScriptPath. Run this install.ps1 from the repository root."
}

# Copy the default config to the user's folder on first install,
# without overwriting any edits the user already made.
$userConfigDir = Join-Path $env:LOCALAPPDATA 'eman-openagent'
$userConfigPath = Join-Path $userConfigDir 'agents.json'
if (-not (Test-Path -LiteralPath $userConfigPath)) {
    New-Item -ItemType Directory -Path $userConfigDir -Force | Out-Null
    Copy-Item -LiteralPath $defaultConfigPath -Destination $userConfigPath
    Write-Host "Copied agents config to $userConfigPath (edit this file to add/remove agents)."
}

. (Join-Path $repoRoot 'scripts\Common.ps1')

# Quick-launch: runs the most-used agent directly, no picker. Always
# registered. Position=Bottom keeps it grouped near Windows' own
# "Open in Terminal" entry.
Register-ContextMenuItem -KeyPath 'HKCU:\Software\Classes\Directory\shell\OpenAgentQuick' -Label 'Open Agent' -ScriptPath $quickScriptPath -PathToken '%1' -Position 'Bottom'
Register-ContextMenuItem -KeyPath 'HKCU:\Software\Classes\Directory\Background\shell\OpenAgentQuick' -Label 'Open Agent' -ScriptPath $quickScriptPath -PathToken '%V' -Position 'Bottom'

# "Choose Agent..." (the full picker) is only worth showing when there's
# more than one agent detected. Sync-ContextMenu adds/removes it based on
# what's actually installed right now, and gives "Open Agent" its real
# label right away instead of a generic placeholder.
Sync-ContextMenu

Write-Host "'Open Agent' menu installed successfully." -ForegroundColor Green
Write-Host "If it doesn't show up right away, restart Explorer (or log off/on)."
