<#  Typora offline-hook universal deployer (u1)
    Deploys the hook from ..\hook\ (default: launch.dist.js) into Typora's resources\app.asar.

    - Auto-detects Typora path (running process / registry / shortcuts / common dirs)
    - First run on a machine : creates app.asar.bak + app.bak\ (original files, from a stock asar)
    - Repeat runs            : rebuilds from app.bak\ (never treats a modified file as original)
    - -Check    : dry run, read-only
    - -HookFile : deploy a different hook (default: .\launch.dist.js)
    - -Force    : override the "looks modified" guard when extracting originals
    - -Restart  : relaunch Typora when done
    - -TyporaPath : explicit install dir if auto-detect fails
#>
param(
  [string]$TyporaPath = "",
  [string]$HookFile = "",
  [switch]$Check,
  [switch]$Force,
  [switch]$Restart
)
$ErrorActionPreference = 'Stop'

function Find-TyporaPath {
  $p = Get-Process Typora -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
  if ($p) { $d = Split-Path $p.Path -Parent; if (Test-Path (Join-Path $d 'resources\app.asar')) { return $d } }
  foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Typora.exe','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Typora.exe')) {
    $r = Get-ItemProperty $root -ErrorAction SilentlyContinue
    if ($r -and $r.'(default)') { $d = Split-Path $r.'(default)' -Parent; if (Test-Path (Join-Path $d 'resources\app.asar')) { return $d } }
  }
  $sh = New-Object -ComObject WScript.Shell
  $dirs = @("$env:USERPROFILE\Desktop", "$env:PUBLIC\Desktop", "$env:APPDATA\Microsoft\Windows\Start Menu", "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar")
  foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) { continue }
    $lnks = Get-ChildItem $dir -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)typora' }
    foreach ($l in $lnks) {
      try { $t = ($sh.CreateShortcut($l.FullName)).TargetPath } catch { continue }
      if ($t -and ($t -match '(?i)Typora\.exe$')) {
        $d = Split-Path $t -Parent
        if (Test-Path (Join-Path $d 'resources\app.asar')) { return $d }
      }
    }
  }
  foreach ($d in @("$env:ProgramFiles\Typora", "${env:ProgramFiles(x86)}\Typora", "$env:LOCALAPPDATA\Programs\Typora", "D:\Typora")) {
    if (Test-Path (Join-Path $d 'resources\app.asar')) { return $d }
  }
  return $null
}

function Read-AsarHeader($Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $headerLen = [System.BitConverter]::ToUInt32($bytes, 4)
  $jsonLen   = [System.BitConverter]::ToInt32($bytes, 12)
  $jsonStr   = [Text.Encoding]::UTF8.GetString($bytes, 16, $jsonLen)
  $obj = $jsonStr | ConvertFrom-Json
  return @{ Files = $obj.files; Base = 8 + $headerLen; Bytes = $bytes }
}

function Extract-AsarFile($Info, $Name) {
  $n = $Info.Files.PSObject.Properties[$Name].Value
  if (!$n) { throw "member not found in asar: $Name" }
  $s = $Info.Base + [int]$n.offset
  return $Info.Bytes[$s..($s + $n.size - 1)]
}

function New-AsarFile($Path, $Entries) {
  $files = [ordered]@{}; $off = 0
  foreach ($k in $Entries.Keys) {
    $files[$k] = @{ size = $Entries[$k].Length; offset = "$off" }
    $off += $Entries[$k].Length
  }
  $json  = (@{ files = $files } | ConvertTo-Json -Compress -Depth 5)
  $jsonB = [Text.Encoding]::UTF8.GetBytes($json)
  $pad   = (4 - $jsonB.Length % 4) % 4
  $sp = 4 + $jsonB.Length + $pad
  $hp = [byte[]]::new(4 + $sp)
  [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]$sp), 0, $hp, 0, 4)
  [Buffer]::BlockCopy([BitConverter]::GetBytes([int32]$jsonB.Length), 0, $hp, 4, 4)
  [Buffer]::BlockCopy($jsonB, 0, $hp, 8, $jsonB.Length)
  $sp2 = [byte[]]::new(8)
  [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]4), 0, $sp2, 0, 4)
  [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]$hp.Length), 0, $sp2, 4, 4)
  $fs = [IO.File]::Open($Path, [IO.FileMode]::Create)
  try {
    $fs.Write($sp2, 0, 8); $fs.Write($hp, 0, $hp.Length)
    foreach ($k in $Entries.Keys) { $fs.Write($Entries[$k], 0, $Entries[$k].Length) }
  } finally { $fs.Close() }
}

function Get-Hex($bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLower()
}

try {
  if (-not $HookFile) { $HookFile = Join-Path $PSScriptRoot '..\hook\launch.dist.js' }
  if (-not (Test-Path $HookFile)) { Write-Host ("X hook not found: " + $HookFile); exit 1 }
  $hookB = [IO.File]::ReadAllBytes($HookFile)
  if ($hookB.Length -lt 500) { Write-Host ("X hook too small (" + $hookB.Length + " bytes): " + $HookFile); exit 1 }
  $hookHash = (Get-Hex $hookB).Substring(0,16)

  if (-not $TyporaPath) { $TyporaPath = Find-TyporaPath }
  if (-not $TyporaPath -or -not (Test-Path (Join-Path $TyporaPath 'Typora.exe'))) {
    Write-Host "X Typora not found. Use:  deploy.ps1 -TyporaPath 'D:\Typora'"
    exit 1
  }

  $res     = Join-Path $TyporaPath 'resources'
  $asar    = Join-Path $res 'app.asar'
  $bakAsar = Join-Path $res 'app.asar.bak'
  $bakDir  = Join-Path $res 'app.bak'

  Write-Host ("== Typora : " + $TyporaPath)
  Write-Host ("== hook   : " + (Split-Path $HookFile -Leaf) + "  sha256:" + $hookHash)
  Write-Host ("== mode   : " + $(if ($Check) { 'CHECK (no changes)' } else { 'DEPLOY' }))

  $bakOk = (Test-Path (Join-Path $bakDir 'package.json')) -and (Test-Path (Join-Path $bakDir 'atom.compiled.dist.jsc')) -and (Test-Path (Join-Path $bakDir 'launch.dist.js'))
  $pkgB = $null; $jscB = $null; $srcNote = ''
  if ($bakOk) {
    $pkgB = [IO.File]::ReadAllBytes((Join-Path $bakDir 'package.json'))
    $jscB = [IO.File]::ReadAllBytes((Join-Path $bakDir 'atom.compiled.dist.jsc'))
    $srcNote = 'app.bak (existing backup)'
  } else {
    $cand = $null
    foreach ($spec in @(@{ p = $asar; n = 'current app.asar' }, @{ p = $bakAsar; n = 'app.asar.bak' })) {
      if (-not (Test-Path $spec.p)) { continue }
      try {
        $info = Read-AsarHeader $spec.p
        $lj = Extract-AsarFile $info 'launch.dist.js'
        if (($lj.Length -lt 4096) -or $Force) { $cand = @{ src = $spec.p; info = $info; note = $spec.n; lj = $lj }; break }
        Write-Host (".. skip " + $spec.n + ": launch.dist.js = " + $lj.Length + " bytes (looks modified; use -Force to override)")
      } catch { Write-Host (".. skip " + $spec.n + ": " + $_.Exception.Message) }
    }
    if (-not $cand) { Write-Host 'X No stock original found (app.bak missing; app.asar and app.asar.bak both look modified).'; exit 1 }
    $pkgB = Extract-AsarFile $cand.info 'package.json'
    $jscB = Extract-AsarFile $cand.info 'atom.compiled.dist.jsc'
    $srcNote = $cand.note
    if ($Check) {
      Write-Host (".. would extract originals from: " + $srcNote)
    } else {
      if (($cand.src -eq $asar) -and (-not (Test-Path $bakAsar))) { Copy-Item $asar $bakAsar -Force; Write-Host '-- created app.asar.bak' }
      New-Item -ItemType Directory $bakDir -Force | Out-Null
      [IO.File]::WriteAllBytes((Join-Path $bakDir 'package.json'), $pkgB)
      [IO.File]::WriteAllBytes((Join-Path $bakDir 'atom.compiled.dist.jsc'), $jscB)
      [IO.File]::WriteAllBytes((Join-Path $bakDir 'launch.dist.js'), $cand.lj)
      Write-Host ("-- created app.bak\ from: " + $srcNote)
    }
  }

  if (Test-Path $asar) {
    try {
      $i0 = Read-AsarHeader $asar
      $lj0 = Extract-AsarFile $i0 'launch.dist.js'
      Write-Host ("== current app.asar : " + (Get-Item $asar).Length + " bytes, launch.dist.js " + $lj0.Length + " bytes, sha256:" + (Get-Hex $lj0).Substring(0,16))
    } catch { Write-Host ("== current app.asar : unreadable (" + $_.Exception.Message + ")") }
  } else { Write-Host '== current app.asar : MISSING' }
  Write-Host ("== originals        : " + $srcNote)

  if ($Check) { Write-Host '== CHECK complete (no changes).'; exit 0 }

  Get-Process Typora -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep 1

  New-AsarFile $asar ([ordered]@{
    'launch.dist.js'         = $hookB
    'atom.compiled.dist.jsc' = $jscB
    'package.json'           = $pkgB
  })
  Write-Host '-- rebuilt app.asar'

  $chk = Read-AsarHeader $asar
  $vLj = Extract-AsarFile $chk 'launch.dist.js'
  if ((Get-Hex $vLj) -ne (Get-Hex $hookB)) { throw 'VERIFY FAILED: hook hash mismatch after rebuild' }
  $ver = ([Text.Encoding]::UTF8.GetString($pkgB) | ConvertFrom-Json).version
  Write-Host ("-- verify OK | version: " + $ver + " | new asar: " + (Get-Item $asar).Length + " bytes")
  if ($Restart) { Start-Process (Join-Path $TyporaPath 'Typora.exe'); Write-Host '-- Typora restarted' }
  Write-Host '== DONE'
} catch {
  Write-Host ("X " + $_.Exception.Message)
  Write-Host '  If "Access denied": run this script as Administrator and make sure Typora is closed.'
  exit 1
}
