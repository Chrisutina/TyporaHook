<#  TyporaHook verify.ps1 (v2.1.0) - READ-ONLY health check.

    Checks : hook version inside app.asar, backup chain (app.bak\, app.asar.bak),
             license registry values, CDP port 9223, running process state.
    Usage  : powershell -NoProfile -ExecutionPolicy Bypass -File verify.ps1 [-TyporaPath "D:\Typora"]
#>
param([string]$TyporaPath = "")
$ErrorActionPreference = 'Continue'

$KNOWN = @{
  'ba544fc356c59987' = 'v2b (current)'
  'e616232d646d4f2d' = 'v1 (DreamNya original)'
  '3ec9df885d96feaa' = 'stock (official loader)'
}
function Get-Hex($bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLower()
}
function Read-AsarLaunchDist($asar) {
  $bytes = [System.IO.File]::ReadAllBytes($asar)
  $headerLen = [System.BitConverter]::ToUInt32($bytes, 4)
  $jsonLen   = [System.BitConverter]::ToInt32($bytes, 12)
  $obj = ([Text.Encoding]::UTF8.GetString($bytes, 16, $jsonLen) | ConvertFrom-Json).files
  $n = $obj.PSObject.Properties['launch.dist.js'].Value
  $s = 8 + $headerLen + [int]$n.offset
  return $bytes[$s..($s + $n.size - 1)]
}
function Find-TyporaPath {
  $p = Get-Process Typora -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
  if ($p) { $d = Split-Path $p.Path -Parent; if (Test-Path (Join-Path $d 'resources\app.asar')) { return $d } }
  foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Typora.exe','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Typora.exe')) {
    $r = Get-ItemProperty $root -ErrorAction SilentlyContinue
    if ($r -and $r.'(default)') { $d = Split-Path $r.'(default)' -Parent; if (Test-Path (Join-Path $d 'resources\app.asar')) { return $d } }
  }
  foreach ($d in @("$env:ProgramFiles\Typora", "${env:ProgramFiles(x86)}\Typora", "$env:LOCALAPPDATA\Programs\Typora", "D:\Typora")) {
    if (Test-Path (Join-Path $d 'resources\app.asar')) { return $d }
  }
  return $null
}

Write-Host '== TyporaHook verify v2.1.0 (read-only) =='
if (-not $TyporaPath) { $TyporaPath = Find-TyporaPath }
if (-not $TyporaPath -or -not (Test-Path (Join-Path $TyporaPath 'Typora.exe'))) {
  Write-Host 'X Typora not found. Use: verify.ps1 -TyporaPath "D:\Typora"'
  exit 1
}
$exe = Get-Item (Join-Path $TyporaPath 'Typora.exe')
Write-Host ("install      : " + $TyporaPath + "  (Typora.exe v" + $exe.VersionInfo.FileVersion + ")")

$res     = Join-Path $TyporaPath 'resources'
$asar    = Join-Path $res 'app.asar'
$bakAsar = Join-Path $res 'app.asar.bak'
$bakDir  = Join-Path $res 'app.bak'
$verdict = 'UNKNOWN build'

if (Test-Path $asar) {
  try {
    $lj = Read-AsarLaunchDist $asar
    $h16 = (Get-Hex $lj).Substring(0,16)
    $name = $KNOWN[$h16]; if (-not $name) { $name = 'UNKNOWN build' }
    $verdict = $name
    Write-Host ("app.asar     : " + (Get-Item $asar).Length + " B | launch.dist.js " + $lj.Length + " B | " + $h16 + "  -> " + $name)
  } catch { Write-Host ("app.asar     : unreadable - " + $_.Exception.Message) }
} else { Write-Host 'app.asar     : MISSING' }

if (Test-Path $bakAsar) {
  $bh = (Get-Hex ([IO.File]::ReadAllBytes($bakAsar))).Substring(0,16)
  $ok = if ($bh -eq 'd338ccbb58cb030b') { 'stock OK' } else { 'NOT stock (?)' }
  Write-Host ("app.asar.bak : " + (Get-Item $bakAsar).Length + " B | " + $bh + "  -> " + $ok)
} else { Write-Host 'app.asar.bak : MISSING (restore source gone!)' }

$need = @('launch.dist.js','atom.compiled.dist.jsc','package.json')
$missing = @($need | Where-Object { -not (Test-Path (Join-Path $bakDir $_)) })
if ($missing.Count -eq 0) {
  $l16 = (Get-Hex ([IO.File]::ReadAllBytes((Join-Path $bakDir 'launch.dist.js')))).Substring(0,16)
  Write-Host ("app.bak\     : 3 files OK | loader " + $l16 + "  (runtime redirect target)")
} else { Write-Host ("app.bak\     : MISSING [" + ($missing -join ',') + "] (required at runtime!)") }

$lic = Get-ItemProperty 'HKCU:\Software\Typora' -ErrorAction SilentlyContinue
$s1 = if ($lic -and $lic.SLicense) { 'present' } else { 'MISSING' }
$s2 = if ($lic -and $lic.IDate) { 'present' } else { 'MISSING' }
Write-Host ("registry     : HKCU\Software\Typora  SLicense=$s1  IDate=$s2")

$port = @()
if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
  $port = @(Get-NetTCPConnection -LocalPort 9223 -State Listen -ErrorAction SilentlyContinue)
} else {
  $port = @(netstat -ano | Select-String ':9223\s+.*LISTENING')
}
Write-Host ("port 9223    : " + $(if ($port.Count -gt 0) { 'LISTENING (debug port open!)' } else { 'closed (OK)' }))

$procs = @(Get-Process Typora -ErrorAction SilentlyContinue).Count
Write-Host ("procs        : " + $procs + " Typora process(es) running")

Write-Host ''
switch -Wildcard ($verdict) {
  'v2b*'   { Write-Host 'VERDICT: HEALTHY - hook v2b is active.' }
  'v1*'    { Write-Host 'VERDICT: v1 hook active - redeploy recommended (fixes CDP + 530s issues).' }
  'stock*' { Write-Host 'VERDICT: no hook deployed (official loader). Use tools\deploy.cmd to deploy.' }
  default  { Write-Host 'VERDICT: unrecognized state - inspect manually (see docs).' }
}
