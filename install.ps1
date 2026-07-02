#Requires -Version 5.1
<#
.SYNOPSIS
    Instala o item "Abrir agente" no menu de contexto do Explorer
    (clique direito em uma pasta e no espaço vazio dentro de uma pasta).

.DESCRIPTION
    Registra as entradas em HKEY_CURRENT_USER (não precisa de administrador)
    e copia a configuração padrão de agentes para
    %LOCALAPPDATA%\eman-openagent\agents.json, onde pode ser editada
    livremente sem afetar o repositório.
#>

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $repoRoot 'scripts\Invoke-OpenAgent.ps1'
$defaultConfigPath = Join-Path $repoRoot 'config\agents.json'

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Não encontrei $scriptPath. Rode este install.ps1 a partir da raiz do repositório."
}

# Copia a config padrão para a pasta do usuário na primeira instalação,
# sem sobrescrever edições já feitas por ele.
$userConfigDir = Join-Path $env:LOCALAPPDATA 'eman-openagent'
$userConfigPath = Join-Path $userConfigDir 'agents.json'
if (-not (Test-Path -LiteralPath $userConfigPath)) {
    New-Item -ItemType Directory -Path $userConfigDir -Force | Out-Null
    Copy-Item -LiteralPath $defaultConfigPath -Destination $userConfigPath
    Write-Host "Config de agentes copiada para $userConfigPath (edite este arquivo para adicionar/remover agentes)."
}

$menuLabel = 'Abrir agente'
$iconPath = 'powershell.exe,0'

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
    $command = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Path "{1}"' -f $scriptPath, $PathToken
    Set-ItemProperty -Path $cmdKey -Name '(Default)' -Value $command
}

# Clique direito em cima de uma pasta
Register-OpenAgentMenu -KeyPath 'HKCU:\Software\Classes\Directory\shell\OpenAgent' -PathToken '%1'

# Clique direito no espaço vazio dentro de uma pasta
Register-OpenAgentMenu -KeyPath 'HKCU:\Software\Classes\Directory\Background\shell\OpenAgent' -PathToken '%V'

Write-Host "Menu 'Abrir agente' instalado com sucesso." -ForegroundColor Green
Write-Host "Se o item não aparecer de imediato, reinicie o Explorer (ou faça logoff/login)."
