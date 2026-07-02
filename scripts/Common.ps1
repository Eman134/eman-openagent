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

    $agents = @(Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json)
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

# Refreshes the quick-launch context menu label to name the current
# most-used agent, e.g. "Open Claude Code Agent". Registry writes are
# best-effort: if they fail, the menu just keeps showing a stale label
# until the next successful run - not worth failing the whole launch over.
function Update-QuickMenuLabel {
    $ordered = Get-OrderedDetectedAgents
    $label = if ($ordered.Count -gt 0) { 'Open {0} Agent' -f $ordered[0].Agent.name } else { 'Open Agent (quick)' }

    foreach ($keyPath in @(
        'HKCU:\Software\Classes\Directory\shell\OpenAgentQuick',
        'HKCU:\Software\Classes\Directory\Background\shell\OpenAgentQuick'
    )) {
        if (Test-Path -LiteralPath $keyPath) {
            try {
                Set-ItemProperty -Path $keyPath -Name '(Default)' -Value $label -ErrorAction Stop
            }
            catch {
                # Best-effort - see comment above.
            }
        }
    }
}
