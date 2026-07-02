#Requires -Version 5.1
<#
.SYNOPSIS
    Shared config/usage-tracking/menu helpers for Select-Agent.ps1 and
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

function Get-AgentSettingsPath {
    $userSettingsPath = Join-Path (Get-AgentAppDataDir) 'settings.json'
    $defaultSettingsPath = Join-Path $PSScriptRoot '..\config\settings.json'
    if (Test-Path -LiteralPath $userSettingsPath) { $userSettingsPath } else { $defaultSettingsPath }
}

# orderMode: 'recent' (most-recently-used first), 'frequency' (most-used
# first), or 'fixed' (always defaultAgent, regardless of usage). defaultAgent
# is the agent name 'fixed' mode pins to the top - it's remembered even
# while orderMode is 'recent'/'frequency', so switching back to 'fixed'
# later doesn't forget the last pick.
function Get-AgentSettings {
    $settings = @{ orderMode = 'recent'; defaultAgent = $null }
    $settingsPath = Get-AgentSettingsPath
    if (Test-Path -LiteralPath $settingsPath) {
        $raw = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        if ($raw.PSObject.Properties.Name -contains 'orderMode' -and $raw.orderMode) {
            $settings.orderMode = $raw.orderMode
        }
        if ($raw.PSObject.Properties.Name -contains 'defaultAgent' -and $raw.defaultAgent) {
            $settings.defaultAgent = $raw.defaultAgent
        }
    }
    $settings
}

function Save-AgentSettings {
    param([hashtable]$Settings)

    $dir = Get-AgentAppDataDir
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $settingsPath = Join-Path $dir 'settings.json'
    ([PSCustomObject]$Settings | ConvertTo-Json) | Set-Content -LiteralPath $settingsPath -Encoding UTF8
}

# Returns a hashtable of agent name -> @{ count; lastUsed }. lastUsed is a
# monotonic sequence number (not a wall-clock timestamp, to sidestep
# clock-skew/format concerns) - whoever holds the highest number ran last.
function Get-UsageMap {
    $usagePath = Join-Path (Get-AgentAppDataDir) 'usage.json'
    $usage = @{}
    if (Test-Path -LiteralPath $usagePath) {
        $raw = Get-Content -LiteralPath $usagePath -Raw | ConvertFrom-Json
        foreach ($prop in $raw.PSObject.Properties) {
            $entry = $prop.Value
            if ($entry -is [System.Management.Automation.PSCustomObject]) {
                $count = if ($entry.PSObject.Properties.Name -contains 'count') { [int]$entry.count } else { 0 }
                $lastUsed = if ($entry.PSObject.Properties.Name -contains 'lastUsed') { [int]$entry.lastUsed } else { 0 }
            }
            else {
                # Older versions stored a single number per agent (either a
                # use count or a last-used sequence). Reuse it for both so
                # existing history still influences ordering after upgrade.
                $legacy = [int]$entry
                $count = $legacy
                $lastUsed = $legacy
            }
            $usage[$prop.Name] = @{ count = $count; lastUsed = $lastUsed }
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
    # Casting to PSCustomObject routes it through property serialization
    # instead; the nested per-agent hashtables serialize fine once the outer
    # one is a PSCustomObject; only the top-level object hits that check.
    ([PSCustomObject]$Usage | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $usagePath -Encoding UTF8
}

# Bumps both the use count and the last-used sequence number for $AgentName.
function Register-AgentUse {
    param([string]$AgentName)

    $usage = Get-UsageMap
    $maxLastUsed = 0
    foreach ($entry in $usage.Values) {
        if ($entry.lastUsed -gt $maxLastUsed) { $maxLastUsed = $entry.lastUsed }
    }

    $current = if ($usage.ContainsKey($AgentName)) { $usage[$AgentName] } else { @{ count = 0; lastUsed = 0 } }
    $current.count = $current.count + 1
    $current.lastUsed = $maxLastUsed + 1
    $usage[$AgentName] = $current
    Save-UsageMap -Usage $usage
}

# Installed agents only, ordered per current settings.orderMode: most-
# recently-used, most-used, or fixed (settings.defaultAgent always on top,
# if still detected). Ties keep the order from agents.json (no reliance
# on Sort-Object's stability, which differs between PS 5.1 and 7+).
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
    $settings = Get-AgentSettings

    $detected = @()
    $originalIndex = 0
    foreach ($agent in $agents) {
        if (Get-Command $agent.checkCommand -ErrorAction SilentlyContinue) {
            $stats = if ($usage.ContainsKey($agent.name)) { $usage[$agent.name] } else { @{ count = 0; lastUsed = 0 } }
            $detected += [PSCustomObject]@{
                Agent         = $agent
                Count         = $stats.count
                LastUsed      = $stats.lastUsed
                OriginalIndex = $originalIndex
            }
        }
        $originalIndex++
    }

    $sortProperty = if ($settings.orderMode -eq 'frequency') { 'Count' } else { 'LastUsed' }
    $sorted = @($detected | Sort-Object -Property @{Expression = $sortProperty; Descending = $true }, OriginalIndex)

    # 'fixed' mode always puts defaultAgent on top, independent of how
    # often or how recently anything was used. If it's no longer detected
    # (e.g. uninstalled), this silently falls back to the recent/frequency
    # order above instead of erroring.
    if ($settings.orderMode -eq 'fixed' -and $settings.defaultAgent) {
        $pinned = @($sorted | Where-Object { $_.Agent.name -eq $settings.defaultAgent })
        if ($pinned.Count -gt 0) {
            $rest = @($sorted | Where-Object { $_.Agent.name -ne $settings.defaultAgent })
            $sorted = @($pinned) + $rest
        }
    }

    # A leading comma is required here: without it, a 1-element array
    # crossing a function's output stream gets unrolled into just that
    # element, and the caller loses .Count/array indexing entirely.
    , $sorted
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

# Renders a mouse-clickable, keyboard-navigable list directly in the
# current console and returns the 0-based index the user picked, or $null
# if they cancelled (Esc). Shared by the main agent picker and the
# settings sub-menus in Select-Agent.ps1 so the Win32 console P/Invoke
# plumbing only has to exist once.
function Read-ConsoleMenuChoice {
    param(
        [string[]]$Items,
        [string[]]$HeaderLines
    )

    if (-not ('OpenAgentConsole' -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class OpenAgentConsole
{
    public const int STD_INPUT_HANDLE = -10;
    public const uint ENABLE_MOUSE_INPUT = 0x0010;
    public const uint ENABLE_EXTENDED_FLAGS = 0x0080;
    public const uint ENABLE_QUICK_EDIT_MODE = 0x0040;

    public const ushort KEY_EVENT = 0x0001;
    public const ushort MOUSE_EVENT = 0x0002;

    public const uint FROM_LEFT_1ST_BUTTON_PRESSED = 0x0001;

    [StructLayout(LayoutKind.Sequential)]
    public struct COORD
    {
        public short X;
        public short Y;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct KEY_EVENT_RECORD
    {
        [MarshalAs(UnmanagedType.Bool)]
        public bool bKeyDown;
        public ushort wRepeatCount;
        public ushort wVirtualKeyCode;
        public ushort wVirtualScanCode;
        public char UnicodeChar;
        public uint dwControlKeyState;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSE_EVENT_RECORD
    {
        public COORD dwMousePosition;
        public uint dwButtonState;
        public uint dwControlKeyState;
        public uint dwEventFlags;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUT_RECORD
    {
        [FieldOffset(0)] public ushort EventType;
        [FieldOffset(4)] public KEY_EVENT_RECORD KeyEvent;
        [FieldOffset(4)] public MOUSE_EVENT_RECORD MouseEvent;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadConsoleInput(IntPtr hConsoleInput, [Out] INPUT_RECORD[] lpBuffer, uint nLength, out uint lpNumberOfEventsRead);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool FlushConsoleInputBuffer(IntPtr hConsoleInput);
}
'@
    }

    function Draw-ConsoleChoiceMenu {
        param([int]$SelectedIndex)

        [Console]::SetCursorPosition(0, $script:menuStartRow)
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $prefix = if ($i -eq $SelectedIndex) { '> ' } else { '  ' }
            $line = "{0}[{1}] {2}" -f $prefix, ($i + 1), $Items[$i]
            $line = $line.PadRight([Console]::WindowWidth - 1)
            if ($i -eq $SelectedIndex) {
                Write-Host $line -ForegroundColor Black -BackgroundColor Green
            }
            else {
                Write-Host $line
            }
        }
    }

    $hIn = [OpenAgentConsole]::GetStdHandle([OpenAgentConsole]::STD_INPUT_HANDLE)
    $prevMode = 0
    [OpenAgentConsole]::GetConsoleMode($hIn, [ref]$prevMode) | Out-Null
    # Clear quick-edit mode (it swallows clicks for text selection instead of
    # delivering them to the app) and turn on mouse + extended flags.
    $newMode = ($prevMode -band (-bnot [OpenAgentConsole]::ENABLE_QUICK_EDIT_MODE)) `
        -bor [OpenAgentConsole]::ENABLE_EXTENDED_FLAGS `
        -bor [OpenAgentConsole]::ENABLE_MOUSE_INPUT
    [OpenAgentConsole]::SetConsoleMode($hIn, $newMode) | Out-Null
    [OpenAgentConsole]::FlushConsoleInputBuffer($hIn) | Out-Null

    $selectedIndex = 0
    $chosenIndex = $null
    $cancelled = $false

    try {
        Clear-Host
        foreach ($h in $HeaderLines) { Write-Host $h -ForegroundColor Cyan }
        Write-Host ''
        Write-Host 'Click an item, use arrows + Enter, press a number, or Esc to cancel.' -ForegroundColor DarkGray
        Write-Host 'Created by @Eman134/eman-openagent' -ForegroundColor DarkGray
        Write-Host ''
        $script:menuStartRow = [Console]::CursorTop
        Draw-ConsoleChoiceMenu -SelectedIndex $selectedIndex

        :inputLoop while ($true) {
            $records = New-Object 'OpenAgentConsole+INPUT_RECORD[]' 1
            $numRead = 0
            [OpenAgentConsole]::ReadConsoleInput($hIn, $records, 1, [ref]$numRead) | Out-Null
            $rec = $records[0]

            if ($rec.EventType -eq [OpenAgentConsole]::KEY_EVENT -and $rec.KeyEvent.bKeyDown) {
                switch ($rec.KeyEvent.wVirtualKeyCode) {
                    38 { $selectedIndex = [Math]::Max(0, $selectedIndex - 1); Draw-ConsoleChoiceMenu -SelectedIndex $selectedIndex } # Up
                    40 { $selectedIndex = [Math]::Min($Items.Count - 1, $selectedIndex + 1); Draw-ConsoleChoiceMenu -SelectedIndex $selectedIndex } # Down
                    13 { $chosenIndex = $selectedIndex; break inputLoop } # Enter
                    27 { $cancelled = $true; break inputLoop } # Esc
                    default {
                        $ch = $rec.KeyEvent.UnicodeChar
                        if ($ch -match '^[1-9]$') {
                            $idx = [int]([string]$ch) - 1
                            if ($idx -lt $Items.Count) { $chosenIndex = $idx; break inputLoop }
                        }
                    }
                }
            }
            elseif ($rec.EventType -eq [OpenAgentConsole]::MOUSE_EVENT) {
                $rowIndex = $rec.MouseEvent.dwMousePosition.Y - $script:menuStartRow
                $isMove = $rec.MouseEvent.dwEventFlags -eq 1
                $isClick = $rec.MouseEvent.dwEventFlags -eq 0 -and ($rec.MouseEvent.dwButtonState -band [OpenAgentConsole]::FROM_LEFT_1ST_BUTTON_PRESSED)

                if ($rowIndex -ge 0 -and $rowIndex -lt $Items.Count) {
                    if ($isClick) {
                        $chosenIndex = $rowIndex; break inputLoop
                    }
                    elseif ($isMove -and $rowIndex -ne $selectedIndex) {
                        $selectedIndex = $rowIndex
                        Draw-ConsoleChoiceMenu -SelectedIndex $selectedIndex
                    }
                }
            }
        }
    }
    finally {
        [OpenAgentConsole]::SetConsoleMode($hIn, $prevMode) | Out-Null
    }

    if ($cancelled) { return $null }
    $chosenIndex
}
