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
$scriptPath = Join-Path $repoRoot 'scripts\Select-Agent.ps1'
$defaultConfigPath = Join-Path $repoRoot 'config\agents.json'

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Could not find $scriptPath. Run this install.ps1 from the repository root."
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

$iconPath = Join-Path $repoRoot 'assets\icon.ico'
$quickScriptPath = Join-Path $repoRoot 'scripts\Run-Agent.ps1'

function Register-ContextMenuItem {
    param(
        [string]$KeyPath,
        [string]$Label,
        [string]$ScriptPath,
        [string]$PathToken,
        [string]$Position
    )

    New-Item -Path $KeyPath -Force | Out-Null
    Set-ItemProperty -Path $KeyPath -Name '(Default)' -Value $Label
    Set-ItemProperty -Path $KeyPath -Name 'Icon' -Value $iconPath
    if ($Position) {
        Set-ItemProperty -Path $KeyPath -Name 'Position' -Value $Position
    }

    $cmdKey = Join-Path $KeyPath 'command'
    New-Item -Path $cmdKey -Force | Out-Null
    $command = 'wt.exe -d "{0}" powershell -NoExit -ExecutionPolicy Bypass -File "{1}" -Path "{0}"' -f $PathToken, $ScriptPath
    Set-ItemProperty -Path $cmdKey -Name '(Default)' -Value $command
}

# Both items get Position=Top so they land together at the top of the
# menu, next to each other, instead of one at the top and the other
# wherever Explorer's default alphabetical ordering would put it.

# Quick-launch: runs the most-used agent directly, no picker.
Register-ContextMenuItem -KeyPath 'HKCU:\Software\Classes\Directory\shell\OpenAgentQuick' -Label 'Open Agent' -ScriptPath $quickScriptPath -PathToken '%1' -Position 'Top'
Register-ContextMenuItem -KeyPath 'HKCU:\Software\Classes\Directory\Background\shell\OpenAgentQuick' -Label 'Open Agent' -ScriptPath $quickScriptPath -PathToken '%V' -Position 'Top'

# Full picker: choose among every detected agent.
Register-ContextMenuItem -KeyPath 'HKCU:\Software\Classes\Directory\shell\OpenAgent' -Label 'Choose Agent...' -ScriptPath $scriptPath -PathToken '%1' -Position 'Top'
Register-ContextMenuItem -KeyPath 'HKCU:\Software\Classes\Directory\Background\shell\OpenAgent' -Label 'Choose Agent...' -ScriptPath $scriptPath -PathToken '%V' -Position 'Top'

# Give the quick-launch item its real label right away, based on current usage.
. (Join-Path $repoRoot 'scripts\Common.ps1')
Update-QuickMenuLabel

Write-Host "'Open Agent' and 'Choose Agent...' menus installed successfully." -ForegroundColor Green
Write-Host "If the items don't show up right away, restart Explorer (or log off/on)."
