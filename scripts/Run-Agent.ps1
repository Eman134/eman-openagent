#Requires -Version 5.1
<#
.SYNOPSIS
    Quick-launch entry point: runs the top agent (per current settings -
    most-recently-used, most-used, or a pinned default) directly, with no
    picker. Backs the "Open <Agent> Agent" context menu item, whose label
    and visibility are kept in sync via Sync-ContextMenu.

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

$ordered = Get-OrderedDetectedAgents

if ($ordered.Count -eq 0) {
    Write-Host "No AI agent was found on PATH (claude, codex, copilot, gemini, deepseek...)." -ForegroundColor Yellow
    Write-Host "Install one of them, or edit:`n$(Join-Path (Get-AgentAppDataDir) 'agents.json')"
    Read-Host 'Press Enter to close'
    exit 0
}

$chosen = $ordered[0]

Register-AgentUse -AgentName $chosen.Agent.name
Sync-ContextMenu

Clear-Host
Write-Host "Open agent in [$Path]" -ForegroundColor Cyan
Write-Host "Launching $($chosen.Agent.name)..." -ForegroundColor Green
Write-Host ''

Set-Location -LiteralPath $Path
# Config-provided command, not external/untrusted input - safe to expand.
Invoke-Expression $chosen.Agent.runCommand
