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

$menuLabel = 'Open Agent'
$iconPath = Join-Path $repoRoot 'assets\icon.ico'

function Register-OpenAgentMenu {
    param(
        [string]$KeyPath,
        [string]$PathToken
    )

    New-Item -Path $KeyPath -Force | Out-Null
    Set-ItemProperty -Path $KeyPath -Name '(Default)' -Value $menuLabel
    Set-ItemProperty -Path $KeyPath -Name 'Icon' -Value $iconPath

    $cmdKey = Join-Path $KeyPath 'command'
    New-Item -Path $cmdKey -Force | Out-Null
    $command = 'wt.exe -d "{0}" powershell -NoExit -ExecutionPolicy Bypass -File "{1}" -Path "{0}"' -f $PathToken, $scriptPath
    Set-ItemProperty -Path $cmdKey -Name '(Default)' -Value $command
}

# Right-click on a folder
Register-OpenAgentMenu -KeyPath 'HKCU:\Software\Classes\Directory\shell\OpenAgent' -PathToken '%1'

# Right-click on empty space inside a folder
Register-OpenAgentMenu -KeyPath 'HKCU:\Software\Classes\Directory\Background\shell\OpenAgent' -PathToken '%V'

Write-Host "'Open Agent' menu installed successfully." -ForegroundColor Green
Write-Host "If the item doesn't show up right away, restart Explorer (or log off/on)."
