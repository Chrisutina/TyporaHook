<#  TyporaHook build-release.ps1 (v2.3.0) - package a release zip.

    Produces : release\TyporaHook-v<Version>.zip  (+ .sha256 file, + MANIFEST.txt inside the zip)
    Contents : docs + hook + payload + tools + README + CHANGELOG + LICENSE (+ clean sandbox skeleton)
    Usage    : powershell -NoProfile -ExecutionPolicy Bypass -File build-release.ps1 [-Version 2.1.0]
#>
param([string]$Version = '2.3.0')
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$rel  = Join-Path $root 'release'
New-Item -ItemType Directory $rel -Force | Out-Null

$stage = Join-Path $env:TEMP ('TyporaHook-stage-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$pkg   = Join-Path $stage 'TyporaHook'
New-Item -ItemType Directory $pkg -Force | Out-Null

foreach ($item in @('docs','hook','payload','tools','tests','README.md','CHANGELOG.md','LICENSE.md')) {
  Copy-Item (Join-Path $root $item) $pkg -Recurse -Force
}
# strip sandbox run artifacts that may exist locally
$clean = @('app.asar','app.asar.bak','app.asar.hooked.bak')
foreach ($f in $clean) { Remove-Item (Join-Path $pkg ('tests\sandbox\FakeTypora\resources\' + $f)) -Force -ErrorAction SilentlyContinue }
Remove-Item (Join-Path $pkg 'tests\sandbox\FakeTypora\resources\app.bak') -Recurse -Force -ErrorAction SilentlyContinue

$hookHash  = (Get-FileHash (Join-Path $root 'hook\launch.dist.js') -Algorithm SHA256).Hash.ToLower()
$stockHash = (Get-FileHash (Join-Path $root 'payload\app.asar.stock-1.14.9.bak') -Algorithm SHA256).Hash.ToLower()
$mf = @(
  ('TyporaHook release v' + $Version)
  ('built: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
  ('hook    : launch.dist.js sha256 = ' + $hookHash)
  ('payload : app.asar.stock-1.14.9.bak sha256 = ' + $stockHash)
  ''
  'Usage: unzip anywhere -> tools\deploy.cmd to deploy; tools\restore.cmd to restore official.'
)
Set-Content -Path (Join-Path $pkg 'MANIFEST.txt') -Value $mf -Encoding Ascii

$zip = Join-Path $rel ('TyporaHook-v' + $Version + '.zip')
Compress-Archive -Path $pkg -DestinationPath $zip -Force
$h = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
Set-Content -Path ($zip + '.sha256') -Value ($h + '  TyporaHook-v' + $Version + '.zip') -Encoding Ascii

Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ('== built : ' + $zip)
Write-Host ('== sha256: ' + $h)
