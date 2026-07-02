#Requires -Version 5.1
<#
.SYNOPSIS
    Renders an in-terminal agent picker (mouse-clickable and keyboard-
    navigable), ordered per current settings (most-recently-used,
    most-used, or a fixed agent), then runs the chosen agent in the
    current console, in the given folder. Also hosts the in-picker
    "Settings..." entry for switching between those modes.

.PARAMETER Path
    Folder to open the agent in. Passed by the Explorer context menu
    item (%1 or %V), or by whoever launches this script.
#>
param(
    [Parameter(Position = 0)]
    [string]$Path = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "Folder not found: $Path" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}

. (Join-Path $PSScriptRoot 'Common.ps1')

function Show-AgentSettingsMenu {
    while ($true) {
        $settings = Get-AgentSettings
        $orderLabel = switch ($settings.orderMode) {
            'frequency' { 'Most used' }
            'fixed' { 'Fixed' }
            default { 'Most recently used' }
        }
        $fixedLabel = if ($settings.defaultAgent) { $settings.defaultAgent } else { '(not set)' }

        $items = @(
            "Order by: $orderLabel (click to switch)"
            "Fixed agent: $fixedLabel (click to change)"
            'Back'
        )
        $idx = Read-ConsoleMenuChoice -Items $items -HeaderLines @('Open Agent settings')

        if ($null -eq $idx -or $idx -eq $items.Count - 1) {
            return
        }

        if ($idx -eq 0) {
            $settings.orderMode = switch ($settings.orderMode) {
                'recent' { 'frequency' }
                'frequency' { 'fixed' }
                default { 'recent' }
            }
            Save-AgentSettings -Settings $settings
        }
        elseif ($idx -eq 1) {
            $ordered = Get-OrderedDetectedAgents
            $names = @($ordered | ForEach-Object { $_.Agent.name }) + 'Clear fixed agent'
            $pick = Read-ConsoleMenuChoice -Items $names -HeaderLines @('Pick the fixed agent')
            if ($null -ne $pick) {
                if ($names[$pick] -eq 'Clear fixed agent') {
                    $settings.defaultAgent = $null
                    if ($settings.orderMode -eq 'fixed') { $settings.orderMode = 'recent' }
                }
                else {
                    $settings.defaultAgent = $names[$pick]
                    $settings.orderMode = 'fixed'
                }
                Save-AgentSettings -Settings $settings
            }
        }
    }
}

$ordered = Get-OrderedDetectedAgents

if ($ordered.Count -eq 0) {
    Write-Host "No AI agent was found on PATH (claude, codex, copilot, gemini, deepseek...)." -ForegroundColor Yellow
    Write-Host "Install one of them, or edit:`n$(Join-Path (Get-AgentAppDataDir) 'agents.json')"
    Read-Host 'Press Enter to close'
    exit 0
}

if ($ordered.Count -eq 1) {
    $chosen = $ordered[0]
}
else {
    $displayItems = @($ordered | ForEach-Object { $_.Agent.name }) + 'Settings...'
    $idx = Read-ConsoleMenuChoice -Items $displayItems -HeaderLines @("Open agent in [$Path]")

    if ($null -eq $idx) {
        Clear-Host
        exit 0
    }

    if ($idx -eq $displayItems.Count - 1) {
        Show-AgentSettingsMenu
        # Relaunch fresh so any order-mode/default-agent change applies
        # immediately, instead of re-implementing the picker's redraw here.
        & $PSCommandPath -Path $Path
        exit 0
    }

    $chosen = $ordered[$idx]
}

Register-AgentUse -AgentName $chosen.Agent.name
Sync-ContextMenu

Clear-Host
Write-Host "Open agent in [$Path]" -ForegroundColor Cyan
Write-Host "Launching $($chosen.Agent.name)..." -ForegroundColor Green
Write-Host ''

Set-Location -LiteralPath $Path
# Config-provided command, not external/untrusted input - safe to expand.
Invoke-Expression $chosen.Agent.runCommand
