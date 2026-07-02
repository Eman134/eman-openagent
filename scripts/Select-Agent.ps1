#Requires -Version 5.1
<#
.SYNOPSIS
    Renders an in-terminal agent picker (mouse-clickable and keyboard-
    navigable) sorted by most frequently used first, then runs the
    chosen agent in the current console, in the given folder.

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

if ($ordered.Count -eq 1) {
    $chosen = $ordered[0]
}
else {
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

    function Draw-Menu {
        param([int]$SelectedIndex)

        [Console]::SetCursorPosition(0, $script:menuStartRow)
        for ($i = 0; $i -lt $ordered.Count; $i++) {
            $name = $ordered[$i].Agent.name
            $prefix = if ($i -eq $SelectedIndex) { '> ' } else { '  ' }
            $line = "{0}[{1}] {2}" -f $prefix, ($i + 1), $name
            $line = $line.PadRight([Console]::WindowWidth - 1)
            if ($i -eq $SelectedIndex) {
                Write-Host $line -ForegroundColor Black -BackgroundColor Green
            }
            else {
                Write-Host $line
            }
        }
    }

    try {
        Clear-Host
        Write-Host "Open agent in [$Path]" -ForegroundColor Cyan
        Write-Host ''
        Write-Host 'Click an agent, use arrows + Enter, press a number, or Esc to cancel.' -ForegroundColor DarkGray
        Write-Host ''
        $script:menuStartRow = [Console]::CursorTop

        $selectedIndex = 0
        Draw-Menu -SelectedIndex $selectedIndex

        $chosen = $null
        $cancelled = $false

        :inputLoop while ($true) {
            $records = New-Object 'OpenAgentConsole+INPUT_RECORD[]' 1
            $numRead = 0
            [OpenAgentConsole]::ReadConsoleInput($hIn, $records, 1, [ref]$numRead) | Out-Null
            $rec = $records[0]

            if ($rec.EventType -eq [OpenAgentConsole]::KEY_EVENT -and $rec.KeyEvent.bKeyDown) {
                switch ($rec.KeyEvent.wVirtualKeyCode) {
                    38 { $selectedIndex = [Math]::Max(0, $selectedIndex - 1); Draw-Menu -SelectedIndex $selectedIndex } # Up
                    40 { $selectedIndex = [Math]::Min($ordered.Count - 1, $selectedIndex + 1); Draw-Menu -SelectedIndex $selectedIndex } # Down
                    13 { $chosen = $ordered[$selectedIndex]; break inputLoop } # Enter
                    27 { $cancelled = $true; break inputLoop } # Esc
                    default {
                        $ch = $rec.KeyEvent.UnicodeChar
                        if ($ch -match '^[1-9]$') {
                            $idx = [int]([string]$ch) - 1
                            if ($idx -lt $ordered.Count) { $chosen = $ordered[$idx]; break inputLoop }
                        }
                    }
                }
            }
            elseif ($rec.EventType -eq [OpenAgentConsole]::MOUSE_EVENT) {
                $rowIndex = $rec.MouseEvent.dwMousePosition.Y - $script:menuStartRow
                $isMove = $rec.MouseEvent.dwEventFlags -eq 1
                $isClick = $rec.MouseEvent.dwEventFlags -eq 0 -and ($rec.MouseEvent.dwButtonState -band [OpenAgentConsole]::FROM_LEFT_1ST_BUTTON_PRESSED)

                if ($rowIndex -ge 0 -and $rowIndex -lt $ordered.Count) {
                    if ($isClick) {
                        $chosen = $ordered[$rowIndex]; break inputLoop
                    }
                    elseif ($isMove -and $rowIndex -ne $selectedIndex) {
                        $selectedIndex = $rowIndex
                        Draw-Menu -SelectedIndex $selectedIndex
                    }
                }
            }
        }
    }
    finally {
        [OpenAgentConsole]::SetConsoleMode($hIn, $prevMode) | Out-Null
    }

    if ($cancelled -or $null -eq $chosen) {
        Clear-Host
        exit 0
    }
}

$usage = Get-UsageMap
$usage[$chosen.Agent.name] = $chosen.Count + 1
Save-UsageMap -Usage $usage
Sync-ContextMenu

Clear-Host
Write-Host "Open agent in [$Path]" -ForegroundColor Cyan
Write-Host "Launching $($chosen.Agent.name)..." -ForegroundColor Green
Write-Host ''

Set-Location -LiteralPath $Path
# Config-provided command, not external/untrusted input - safe to expand.
Invoke-Expression $chosen.Agent.runCommand
