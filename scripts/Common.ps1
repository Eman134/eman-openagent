#Requires -Version 5.1
<#
.SYNOPSIS
    Shared config/usage-tracking helpers for Select-Agent.ps1 and
    Run-Agent.ps1. Dot-source this file before calling its functions.
#>

function Get-AgentAppDataDir {
    Join-Path $env:LOCALAPPDATA 'eman-openagent'
}

function Get-AgentsConfigPath {
    $userConfigPath = Join-Path (Get-AgentAppDataDir) 'agents.json'
    $defaultConfigPath = Join-Path $PSScriptRoot '..\config\agents.json'
    if (Test-Path -LiteralPath $userConfigPath) { $userConfigPath } else { $defaultConfigPath }
}

function Get-UsageMap {
    $usagePath = Join-Path (Get-AgentAppDataDir) 'usage.json'
    $usage = @{}
    if (Test-Path -LiteralPath $usagePath) {
        $raw = Get-Content -LiteralPath $usagePath -Raw | ConvertFrom-Json
        foreach ($prop in $raw.PSObject.Properties) {
            $usage[$prop.Name] = [int]$prop.Value
        }
    }
    $usage
}

function Save-UsageMap {
    param([hashtable]$Usage)

    $dir = Get-AgentAppDataDir
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $usagePath = Join-Path $dir 'usage.json'
    # ConvertTo-Json can't serialize a plain (non-generic) Hashtable directly -
    # it reflects on generic dictionary arguments to confirm string keys, which
    # a Hashtable doesn't have, so it always throws NonStringKeyInDictionary.
    # Casting to PSCustomObject routes it through property serialization instead.
    ([PSCustomObject]$Usage | ConvertTo-Json) | Set-Content -LiteralPath $usagePath -Encoding UTF8
}

# Installed agents only, sorted most-used first. Ties keep the order from
# agents.json (no reliance on Sort-Object's stability, which differs
# between PS 5.1 and 7+).
function Get-OrderedDetectedAgents {
    $configPath = Get-AgentsConfigPath
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Config file not found: $configPath"
    }

    # Materialize before wrapping in @(): ConvertFrom-Json emits its whole
    # result as a single non-enumerated pipeline object, so @(... | ConvertFrom-Json)
    # wraps that entire array as ONE element instead of flattening it.
    $parsedAgents = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $agents = @($parsedAgents)
    $usage = Get-UsageMap

    $detected = @()
    $originalIndex = 0
    foreach ($agent in $agents) {
        if (Get-Command $agent.checkCommand -ErrorAction SilentlyContinue) {
            $count = if ($usage.ContainsKey($agent.name)) { $usage[$agent.name] } else { 0 }
            $detected += [PSCustomObject]@{
                Agent         = $agent
                Count         = $count
                OriginalIndex = $originalIndex
            }
        }
        $originalIndex++
    }

    $result = @($detected | Sort-Object -Property @{Expression = 'Count'; Descending = $true }, OriginalIndex)
    # A leading comma is required here: without it, a 1-element array
    # crossing a function's output stream gets unrolled into just that
    # element, and the caller loses .Count/array indexing entirely.
    , $result
}

# Registers (or refreshes) one Explorer context menu verb. Shared by
# install.ps1 and Sync-ContextMenu so there's a single source of truth
# for how these entries are built.
function Register-ContextMenuItem {
    param(
        [string]$KeyPath,
        [string]$Label,
        [string]$ScriptPath,
        [string]$PathToken,
        [string]$Position
    )

    $iconPath = Join-Path $PSScriptRoot '..\assets\icon.ico'

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

function Remove-ContextMenuItemIfExists {
    param([string]$KeyPath)

    if (Test-Path -LiteralPath $KeyPath) {
        Remove-Item -LiteralPath $KeyPath -Recurse -Force
    }
}

# Keeps the Explorer context menu in sync with what's actually detected
# right now: refreshes the "Open Agent" label to name the top pick, and
# only shows "Choose Agent..." when there's more than one agent to
# choose from (with just one, the picker would be pointless). Also used
# right after install, so the menu is correct from the very first run.
# Registry writes are best-effort: if one fails, the menu just keeps
# showing stale state until the next successful run - not worth failing
# the whole launch over.
function Sync-ContextMenu {
    $ordered = Get-OrderedDetectedAgents

    $quickLabel = if ($ordered.Count -gt 0) { 'Open {0} Agent' -f $ordered[0].Agent.name } else { 'Open Agent (quick)' }
    foreach ($keyPath in @(
        'HKCU:\Software\Classes\Directory\shell\OpenAgentQuick',
        'HKCU:\Software\Classes\Directory\Background\shell\OpenAgentQuick'
    )) {
        if (Test-Path -LiteralPath $keyPath) {
            try {
                Set-ItemProperty -Path $keyPath -Name '(Default)' -Value $quickLabel -ErrorAction Stop
            }
            catch {
                # Best-effort - see comment above.
            }
        }
    }

    $choosePairs = @(
        @{ KeyPath = 'HKCU:\Software\Classes\Directory\shell\OpenAgent'; PathToken = '%1' }
        @{ KeyPath = 'HKCU:\Software\Classes\Directory\Background\shell\OpenAgent'; PathToken = '%V' }
    )

    try {
        if ($ordered.Count -le 1) {
            foreach ($pair in $choosePairs) {
                Remove-ContextMenuItemIfExists -KeyPath $pair.KeyPath
            }
        }
        else {
            $selectScriptPath = Join-Path $PSScriptRoot 'Select-Agent.ps1'
            foreach ($pair in $choosePairs) {
                # Position=Bottom keeps it grouped near Windows' own
                # "Open in Terminal" entry, next to our "Open Agent" item.
                Register-ContextMenuItem -KeyPath $pair.KeyPath -Label 'Choose Agent...' -ScriptPath $selectScriptPath -PathToken $pair.PathToken -Position 'Bottom'
            }
        }
    }
    catch {
        # Best-effort - see comment above.
    }
}
