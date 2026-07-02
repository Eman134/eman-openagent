#Requires -Version 5.1
<#
.SYNOPSIS
    Removes the "Open Agent" item from the Explorer context menu.
#>

$ErrorActionPreference = 'Stop'

$paths = @(
    'HKCU:\Software\Classes\Directory\shell\OpenAgent',
    'HKCU:\Software\Classes\Directory\Background\shell\OpenAgent'
)

foreach ($p in $paths) {
    if (Test-Path -LiteralPath $p) {
        Remove-Item -LiteralPath $p -Recurse -Force
    }
}

Write-Host "'Open Agent' menu removed." -ForegroundColor Yellow
Write-Host "The agents config at %LOCALAPPDATA%\eman-openagent\agents.json was kept (delete it manually if you want)."
