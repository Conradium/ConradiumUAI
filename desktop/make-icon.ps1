param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $Source).Path
$destination = [IO.Path]::GetFullPath($Destination)
Add-Type -AssemblyName System.Drawing

# The web favicon is a PNG regardless of its name, so CSC cannot embed it directly.
# This emits a classic uncompressed BGRA .ico that the compiler accepts, at every
# size Windows asks for. 32-bit frames carry transparency in the alpha channel.
function New-IconFrame($bitmap) {
    $size = $bitmap.Width
    $stride = $size * 4
    $locked = $bitmap.LockBits([System.Drawing.Rectangle]::new(0, 0, $size, $size),
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $pixels = [byte[]]::new($stride * $size)
        [System.Runtime.InteropServices.Marshal]::Copy($locked.Scan0, $pixels, 0, $pixels.Length)
    } finally { $bitmap.UnlockBits($locked) }

    $maskStride = [int]([Math]::Floor(($size + 31) / 32) * 4)
    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        # BITMAPINFOHEADER. The doubled height covers the XOR image and the AND mask.
        $writer.Write([UInt32]40)
        $writer.Write([Int32]$size)
        $writer.Write([Int32]($size * 2))
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]0)
        $writer.Write([UInt32]($stride * $size))
        $writer.Write([Int32]0)
        $writer.Write([Int32]0)
        $writer.Write([UInt32]0)
        $writer.Write([UInt32]0)
        for ($row = $size - 1; $row -ge 0; $row--) { $writer.Write($pixels, $row * $stride, $stride) }
        $writer.Write([byte[]]::new($maskStride * $size))
        $writer.Flush()
        Write-Output -NoEnumerate $stream.ToArray()
    } finally { $writer.Dispose(); $stream.Dispose() }
}

$image = [System.Drawing.Image]::FromFile($source)
try {
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $frames = @()
    $payloads = @()
    try {
        foreach ($size in $sizes) {
            $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $frames += ,$bitmap
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.DrawImage($image, 0, 0, $size, $size)
            } finally { $graphics.Dispose() }
        }
        foreach ($bitmap in $frames) { $payloads += ,(New-IconFrame $bitmap) }
    } finally { foreach ($bitmap in $frames) { $bitmap.Dispose() } }

    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([UInt16]0); $writer.Write([UInt16]1); $writer.Write([UInt16]$payloads.Count)
        $offset = 6 + 16 * $payloads.Count
        for ($index = 0; $index -lt $payloads.Count; $index++) {
            # 256 is written as 0 in the one-byte width/height fields.
            $dimension = [byte]$(if ($sizes[$index] -ge 256) { 0 } else { $sizes[$index] })
            $writer.Write($dimension); $writer.Write($dimension)
            $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([UInt16]1); $writer.Write([UInt16]32)
            $writer.Write([UInt32]$payloads[$index].Length)
            $writer.Write([UInt32]$offset)
            $offset += $payloads[$index].Length
        }
        foreach ($payload in $payloads) { $writer.Write($payload) }
        $writer.Flush()
        [IO.File]::WriteAllBytes($destination, $stream.ToArray())
    } finally { $writer.Dispose(); $stream.Dispose() }
} finally { $image.Dispose() }
Write-Output "Wrote $destination ($((Get-Item -LiteralPath $destination).Length) bytes, $($sizes.Count) sizes)"
