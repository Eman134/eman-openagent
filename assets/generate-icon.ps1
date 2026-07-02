#Requires -Version 5.1
<#
.SYNOPSIS
    Generates assets\icon.ico (multi-resolution: 16, 32, 48px) from scratch
    using GDI+. Re-run this after editing the drawing logic below to
    regenerate the icon; the .ico file itself is committed to the repo
    so end users don't need to run this.
#>

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-AgentIconBitmap {
    param([int]$Size)

    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))

    $bg = [System.Drawing.Color]::FromArgb(255, 17, 17, 20)
    $accent = [System.Drawing.Color]::FromArgb(255, 88, 220, 150)

    $g.FillEllipse((New-Object System.Drawing.SolidBrush($bg)), 0, 0, $Size, $Size)

    $s = $Size / 32.0
    $penWidth = [Math]::Max(1.6, 3.2 * $s)
    $pen = New-Object System.Drawing.Pen($accent, $penWidth)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

    $chevron = @(
        (New-Object System.Drawing.PointF ([float](9 * $s)), ([float](9 * $s)))
        (New-Object System.Drawing.PointF ([float](16 * $s)), ([float](16 * $s)))
        (New-Object System.Drawing.PointF ([float](9 * $s)), ([float](23 * $s)))
    )
    $g.DrawLines($pen, $chevron)
    $g.DrawLine($pen, [float](19 * $s), [float](23 * $s), [float](25 * $s), [float](23 * $s))

    $g.Flush()
    return $bmp
}

function New-IcoFile {
    param(
        [int[]]$Sizes,
        [string]$OutPath
    )

    $pngFrames = @()
    foreach ($sz in $Sizes) {
        $bmp = New-AgentIconBitmap -Size $sz
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngFrames += , $ms.ToArray()
        $bmp.Dispose()
    }

    New-Item -ItemType Directory -Path (Split-Path $OutPath -Parent) -Force | Out-Null
    $fs = [System.IO.File]::Open($OutPath, [System.IO.FileMode]::Create)
    try {
        $bw = New-Object System.IO.BinaryWriter($fs)

        $bw.Write([UInt16]0)          # reserved
        $bw.Write([UInt16]1)          # type: icon
        $bw.Write([UInt16]$Sizes.Count)

        $offset = 6 + (16 * $Sizes.Count)
        for ($i = 0; $i -lt $Sizes.Count; $i++) {
            $sz = $Sizes[$i]
            $data = $pngFrames[$i]
            $wByte = if ($sz -ge 256) { 0 } else { $sz }
            $bw.Write([byte]$wByte)   # width (0 = 256)
            $bw.Write([byte]$wByte)   # height (0 = 256)
            $bw.Write([byte]0)        # color count
            $bw.Write([byte]0)        # reserved
            $bw.Write([UInt16]1)      # color planes
            $bw.Write([UInt16]32)     # bits per pixel
            $bw.Write([UInt32]$data.Length)
            $bw.Write([UInt32]$offset)
            $offset += $data.Length
        }

        foreach ($data in $pngFrames) {
            $bw.Write($data)
        }
        $bw.Flush()
    }
    finally {
        $fs.Close()
    }
}

$outPath = Join-Path $PSScriptRoot 'icon.ico'
New-IcoFile -Sizes @(16, 32, 48) -OutPath $outPath
Write-Host "Icon written to $outPath" -ForegroundColor Green

$pngOutPath = Join-Path $PSScriptRoot 'icon.png'
$pngBmp = New-AgentIconBitmap -Size 256
$pngBmp.Save($pngOutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$pngBmp.Dispose()
Write-Host "PNG written to $pngOutPath (for README use)" -ForegroundColor Green
