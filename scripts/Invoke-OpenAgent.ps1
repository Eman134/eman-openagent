#Requires -Version 5.1
<#
.SYNOPSIS
    Detects installed command-line AI agents and opens the chosen one
    in Windows Terminal, in the given folder.

.PARAMETER Path
    Folder where the agent should be opened. Passed by the Explorer
    context menu item (%1 or %V).
#>
param(
    [Parameter(Position = 0)]
    [string]$Path = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Folder not found: $Path",
        'Open Agent',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

# User config (editable) takes priority; otherwise fall back to the repo default.
$userConfigPath = Join-Path $env:LOCALAPPDATA 'eman-openagent\agents.json'
$defaultConfigPath = Join-Path $PSScriptRoot '..\config\agents.json'
$configPath = if (Test-Path -LiteralPath $userConfigPath) { $userConfigPath } else { $defaultConfigPath }

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Config file not found: $configPath"
}

$agents = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

$detected = @()
foreach ($agent in $agents) {
    if (Get-Command $agent.checkCommand -ErrorAction SilentlyContinue) {
        $detected += $agent
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ($detected.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show(
        "No AI agent was found on PATH (claude, codex, copilot, gemini, aider...).`n`nInstall one of them, or edit:`n$userConfigPath",
        'Open Agent',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit 0
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Open agent in: $Path"
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true
$form.Width = 340
$form.Height = 110 + ($detected.Count * 42)

$label = New-Object System.Windows.Forms.Label
$label.Text = 'Choose an agent:'
$label.AutoSize = $true
$label.Left = 20
$label.Top = 15
$form.Controls.Add($label)

$script:selected = $null
$y = 45
foreach ($agent in $detected) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $agent.name
    $btn.Width = 280
    $btn.Height = 34
    $btn.Left = 20
    $btn.Top = $y
    $btn.Tag = $agent
    $btn.Add_Click({
        $script:selected = $this.Tag
        $form.Close()
    })
    $form.Controls.Add($btn)
    $y += 40
}

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

if ($null -eq $script:selected) {
    exit 0
}

$runCommand = $script:selected.runCommand
$wtArgs = '-d "{0}" powershell -NoExit -Command "{1}"' -f $Path, $runCommand

Start-Process -FilePath 'wt.exe' -ArgumentList $wtArgs
