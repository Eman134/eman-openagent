#Requires -Version 5.1
<#
.SYNOPSIS
    Remove o item "Abrir agente" do menu de contexto do Explorer.
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

Write-Host "Menu 'Abrir agente' removido." -ForegroundColor Yellow
Write-Host "A config de agentes em %LOCALAPPDATA%\eman-openagent\agents.json foi mantida (remova manualmente se quiser)."
