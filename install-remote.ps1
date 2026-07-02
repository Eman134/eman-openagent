#Requires -Version 5.1
<#
.SYNOPSIS
    One-line remote installer for eman-openagent - no git required.

.DESCRIPTION
    Downloads the repository as a zip straight from GitHub, extracts it
    to %LOCALAPPDATA%\Programs\eman-openagent, and runs the local
    install.ps1 from there so the context menu points at a permanent
    location on disk.

.EXAMPLE
    irm https://raw.githubusercontent.com/Eman134/eman-openagent/main/install-remote.ps1 | iex
#>

$ErrorActionPreference = 'Stop'

$repoZipUrl = 'https://github.com/Eman134/eman-openagent/archive/refs/heads/main.zip'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\eman-openagent'
$tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "eman-openagent-$([guid]::NewGuid()).zip"
$tempExtract = Join-Path ([System.IO.Path]::GetTempPath()) "eman-openagent-$([guid]::NewGuid())"

Write-Host "Downloading eman-openagent from GitHub..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $repoZipUrl -OutFile $tempZip -UseBasicParsing

Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
Remove-Item -LiteralPath $tempZip -Force

$extractedRoot = Get-ChildItem -LiteralPath $tempExtract -Directory | Select-Object -First 1
if (-not $extractedRoot) {
    throw "Unexpected zip layout - could not find the extracted project folder."
}

if (Test-Path -LiteralPath $installDir) {
    Remove-Item -LiteralPath $installDir -Recurse -Force
}
New-Item -ItemType Directory -Path (Split-Path $installDir -Parent) -Force | Out-Null
Move-Item -LiteralPath $extractedRoot.FullName -Destination $installDir

Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Installed to $installDir" -ForegroundColor Green

& (Join-Path $installDir 'install.ps1')
