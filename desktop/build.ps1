param([string]$Dotnet = 'dotnet')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$desktopRoot = $PSScriptRoot
$repoRoot = Split-Path $desktopRoot -Parent
$cache = Join-Path $desktopRoot '.cache'
$release = Join-Path $desktopRoot 'release'
$stage = Join-Path $desktopRoot ('.build/' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $release 'UAI-Bridge-win-x64'
$archive = Join-Path $release 'UAI-Bridge-1.0.0-win-x64.zip'
$nodeVersion = '24.21.0'
$nodeHash = '158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541'
New-Item -ItemType Directory -Path $cache,$release,$stage -Force | Out-Null
$nodeArchive = Join-Path $cache "node-v$nodeVersion-win-x64.zip"
if (!(Test-Path -LiteralPath $nodeArchive)) {
    Invoke-WebRequest -UseBasicParsing -Uri "https://nodejs.org/dist/v$nodeVersion/node-v$nodeVersion-win-x64.zip" -OutFile $nodeArchive
}
if ((Get-FileHash -LiteralPath $nodeArchive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $nodeHash) {
    throw 'Node archive failed SHA-256 verification. Remove desktop/.cache/node-v24.21.0-win-x64.zip and retry.'
}
$nodeFolder = Join-Path $cache "node-v$nodeVersion-win-x64"
Expand-Archive -LiteralPath $nodeArchive -DestinationPath $cache -Force

$dotnetCommand = (Get-Command $Dotnet -ErrorAction Stop).Source
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
# The shipped web favicon is a PNG, which CSC cannot embed as a Win32 icon, so a
# real multi-size .ico is generated beside the build cache for the launcher.
$icon = Join-Path $cache 'app.ico'
& (Join-Path $desktopRoot 'make-icon.ps1') -Source (Join-Path $repoRoot 'bridge/web/favicon.ico') -Destination $icon
& $dotnetCommand publish (Join-Path $desktopRoot 'src/UaiBridge/UaiBridge.csproj') -c Release -r win-x64 --self-contained true -o $stage -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -p:DebugType=None -p:ApplicationIcon=$icon
if ($LASTEXITCODE -ne 0) { throw 'Desktop publish failed.' }

New-Item -ItemType Directory -Path (Join-Path $stage 'runtime'),(Join-Path $stage 'bridge'),(Join-Path $stage 'client'),(Join-Path $stage 'licenses') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $nodeFolder 'node.exe') -Destination (Join-Path $stage 'runtime/node.exe')
Copy-Item -LiteralPath (Join-Path $nodeFolder 'LICENSE') -Destination (Join-Path $stage 'licenses/Node-LICENSE.txt')
foreach ($file in @('server.js','inference.js','picture-store.js')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "bridge/$file") -Destination (Join-Path $stage "bridge/$file")
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'bridge/web') -Destination (Join-Path $stage 'bridge/web') -Recurse
Copy-Item -LiteralPath (Join-Path $repoRoot 'dist/uai.lua') -Destination (Join-Path $stage 'client/uai.lua')
Copy-Item -LiteralPath (Join-Path $desktopRoot 'START-HERE.txt') -Destination $stage
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $stage 'licenses/Project-UAI-LICENSE.txt')
$dotnetRoot = Split-Path $dotnetCommand -Parent
foreach ($name in @('LICENSE.txt','ThirdPartyNotices.txt')) {
    if (!(Test-Path -LiteralPath (Join-Path $dotnetRoot $name))) { throw "Missing .NET redistribution notice: $name" }
    Copy-Item -LiteralPath (Join-Path $dotnetRoot $name) -Destination (Join-Path $stage "licenses/Dotnet-$name")
}
$files = @(Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName | ForEach-Object {
    [ordered]@{ path = $_.FullName.Substring($stage.Length + 1).Replace('\','/'); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
})
[ordered]@{ product = 'UAI Bridge'; version = '1.0.0'; platform = 'win-x64'; port = 28791; node = $nodeVersion; files = $files } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Encoding UTF8

# Never remove or move a computed directory until its absolute target is checked.
$resolvedPackage = [IO.Path]::GetFullPath($package)
$resolvedRelease = [IO.Path]::GetFullPath($release) + [IO.Path]::DirectorySeparatorChar
if (!$resolvedPackage.StartsWith($resolvedRelease, [StringComparison]::OrdinalIgnoreCase)) { throw 'Package path escaped release folder.' }
if (Test-Path -LiteralPath $resolvedPackage) { Remove-Item -LiteralPath $resolvedPackage -Recurse -Force }
Move-Item -LiteralPath $stage -Destination $resolvedPackage
Compress-Archive -LiteralPath $resolvedPackage -DestinationPath $archive -CompressionLevel Optimal -Force
$digest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$digest  $([IO.Path]::GetFileName($archive))" | Set-Content -LiteralPath ($archive + '.sha256') -Encoding ASCII
Write-Output "Built $archive"
Write-Output 'Inspect the package and manifest before running desktop/verify.ps1.'
