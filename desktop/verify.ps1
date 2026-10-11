$ErrorActionPreference = 'Stop'
$package = Join-Path $PSScriptRoot 'release/UAI-Bridge-win-x64'
$evidence = Join-Path $PSScriptRoot '.build/verification'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$manifest = Get-Content -LiteralPath (Join-Path $package 'manifest.json') -Raw | ConvertFrom-Json
foreach ($file in $manifest.files) {
    $target = [IO.Path]::GetFullPath((Join-Path $package $file.path))
    if (!$target.StartsWith([IO.Path]::GetFullPath($package) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid manifest path' }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) { throw "Package hash mismatch: $($file.path)" }
}
$exe = Join-Path $package 'UAI Bridge.exe'
$result = Join-Path $evidence 'smoke.json'
$process = Start-Process -FilePath $exe -ArgumentList @('--smoke-test',('"' + $result + '"')) -WindowStyle Hidden -PassThru
if (!$process.WaitForExit(60000)) { Stop-Process -Id $process.Id -Force; throw 'Desktop smoke test exceeded 60 seconds.' }
if ($process.ExitCode -ne 0) { Get-Content -LiteralPath $result -ErrorAction SilentlyContinue; throw 'Desktop smoke test failed.' }
Get-Content -LiteralPath $result
$preview = Join-Path $evidence 'launcher.png'
$process = Start-Process -FilePath $exe -ArgumentList @('--render-preview',('"' + $preview + '"')) -WindowStyle Hidden -PassThru
if (!$process.WaitForExit(20000)) { Stop-Process -Id $process.Id -Force; throw 'Desktop preview exceeded 20 seconds.' }
if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $preview)) { throw 'Desktop preview failed.' }
Write-Output "Inspect native window preview: $preview"
