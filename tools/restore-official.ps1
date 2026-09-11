<#  Restore ORIGINAL Typora state (u1)
    Copies resources\app.asar.bak back to app.asar; keeps the modded one as app.asar.hooked.bak.
    -Check          : dry run, read-only
    -CleanRegistry  : also remove HKCU\Software\Typora license values (with .reg backup)
    -Restart        : relaunch Typora when done
    -TyporaPath     : explicit install dir if auto-detect fails
#>
param(
  [string]$TyporaPath = "",
  [switch]$Check,
  [switch]$CleanRegistry,
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

try {
  if (-not $TyporaPath) { $TyporaPath = Find-TyporaPath }
  if (-not $TyporaPath -or -not (Test-Path (Join-Path $TyporaPath 'Typora.exe'))) {
    Write-Host "X Typora not found. Use:  restore-official.ps1 -TyporaPath 'D:\Typora'"
    exit 1
  }
  $res     = Join-Path $TyporaPath 'resources'
  $asar    = Join-Path $res 'app.asar'
  $bakAsar = Join-Path $res 'app.asar.bak'

  Write-Host ("== Typora : " + $TyporaPath)
  if (-not (Test-Path $bakAsar)) {
    Write-Host 'X app.asar.bak not found - nothing to restore from.'
    Write-Host '  (If you have an original asar elsewhere, copy it to resources\app.asar.bak first.)'
    exit 1
  }
  Write-Host ("== app.asar.bak : " + (Get-Item $bakAsar).Length + " bytes")
  if (Test-Path $asar) {
    try {
      $bytes = [System.IO.File]::ReadAllBytes($asar)
      $headerLen = [System.BitConverter]::ToUInt32($bytes, 4)
      $jsonLen   = [System.BitConverter]::ToInt32($bytes, 12)
      $obj = ([Text.Encoding]::UTF8.GetString($bytes, 16, $jsonLen) | ConvertFrom-Json).files
      $n = $obj.PSObject.Properties['launch.dist.js'].Value
      $s = 8 + $headerLen + [int]$n.offset
      $lj = $bytes[$s..($s + $n.size - 1)]
      Write-Host ("== current app.asar : launch.dist.js " + $lj.Length + " bytes (modified if > 4096)")
    } catch { Write-Host '== current app.asar : unreadable' }
  }
  if ($Check) {
    Write-Host ('== would: save current as app.asar.hooked.bak, then restore app.asar from app.asar.bak' + $(if ($CleanRegistry) { '; remove registry values (with .reg backup)' } else { '' }))
    Write-Host '== CHECK complete (no changes).'
    exit 0
  }

  Get-Process Typora -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep 1
  Copy-Item $asar (Join-Path $res 'app.asar.hooked.bak') -Force
  Copy-Item $bakAsar $asar -Force
  Write-Host ("-- restored original app.asar (" + (Get-Item $asar).Length + " bytes)")

  if ($CleanRegistry) {
    $regBak = Join-Path $env:USERPROFILE 'typora-license-backup.reg'
    & reg.exe export 'HKCU\Software\Typora' $regBak /y | Out-Null
    & reg.exe delete 'HKCU\Software\Typora' /v SLicense /f | Out-Null
    & reg.exe delete 'HKCU\Software\Typora' /v IDate /f | Out-Null
    Write-Host ("-- registry values removed (backup: " + $regBak + ")")
  } else {
    Write-Host '-- registry SLicense/IDate kept (use -CleanRegistry to remove; needed again if you re-apply the hook)'
  }
  Write-Host '-- note: app.bak\ and app.asar.bak were kept; delete manually for a fully clean tree'
  if ($Restart) { Start-Process (Join-Path $TyporaPath 'Typora.exe'); Write-Host '-- Typora restarted' }
  Write-Host '== DONE'
} catch {
  Write-Host ("X " + $_.Exception.Message)
  Write-Host '  If "Access denied": run this script as Administrator.'
  exit 1
}
