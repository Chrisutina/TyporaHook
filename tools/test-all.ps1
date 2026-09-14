<#  TyporaHook test-all.ps1 (v2.3.0) - full drill inside the sandbox ONLY.

    Steps : reset sandbox -> deploy v2b -> repeat deploy -> rollback to v1 hook -> restore official.
    Verifies the hook hash inside the rebuilt app.asar at every step.

    WARNING: the deploy step kills any running "Typora" process by name (sandbox or not). Save your work.
#>
$ErrorActionPreference = 'Stop'

$root    = Split-Path $PSScriptRoot -Parent
$sb      = Join-Path $root 'tests\sandbox\FakeTypora'
$res     = Join-Path $sb 'resources'
$payload = Join-Path $root 'payload\app.asar.stock-1.14.9.bak'
$deploy  = Join-Path $PSScriptRoot 'deploy.ps1'
$restore = Join-Path $PSScriptRoot 'restore-official.ps1'
$hookV1  = Join-Path $root 'hook\launch.dist.orig.js'

function Get-Hex($bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLower()
}
function Hook-Of($asar) {
  $bytes = [System.IO.File]::ReadAllBytes($asar)
  $headerLen = [System.BitConverter]::ToUInt32($bytes, 4)
  $jsonLen   = [System.BitConverter]::ToInt32($bytes, 12)
  $obj = ([Text.Encoding]::UTF8.GetString($bytes, 16, $jsonLen) | ConvertFrom-Json).files
  $n = $obj.PSObject.Properties['launch.dist.js'].Value
  $s = 8 + $headerLen + [int]$n.offset
  $lj = $bytes[$s..($s + $n.size - 1)]
  return @{ Size = $lj.Length; H16 = (Get-Hex $lj).Substring(0,16) }
}

$script:pass = 0; $script:fail = 0
function Check($cond, $label) {
  if ($cond) { Write-Host ('  [PASS] ' + $label); $script:pass++ }
  else       { Write-Host ('  [FAIL] ' + $label); $script:fail++ }
}

if (-not (Test-Path $payload)) { throw ('payload not found: ' + $payload) }
Write-Host '== TyporaHook test-all (sandbox drill) =='

# --- step 0: reset sandbox ---
Write-Host ''
Write-Host '[0] reset sandbox'
Remove-Item (Join-Path $res 'app.bak')             -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $res 'app.asar.bak')        -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $res 'app.asar.hooked.bak') -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $res -Force | Out-Null
Copy-Item $payload (Join-Path $res 'app.asar') -Force
if (-not (Test-Path (Join-Path $sb 'Typora.exe'))) { New-Item -ItemType File (Join-Path $sb 'Typora.exe') | Out-Null }
$t = Hook-Of (Join-Path $res 'app.asar')
Check ($t.Size -eq 1383 -and $t.H16 -eq '3ec9df885d96feaa') ('stock before deploy (launch.dist.js ' + $t.Size + ' B)')

# --- step 0b: analyze smoke (sandbox stock vs reference) ---
$analyze = Join-Path $PSScriptRoot 'analyze-version.ps1'
$azOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $analyze -Asar (Join-Path $res 'app.asar') -Quiet) -join "`n"
Check ($azOut -match 'RESULT: IDENTICAL') 'analyze: sandbox stock = reference'

# --- step 1: deploy v2b ---
Write-Host ''
Write-Host '[1] deploy v2b'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $deploy -TyporaPath $sb
Check ($LASTEXITCODE -eq 0) 'deploy exit code 0'
$t = Hook-Of (Join-Path $res 'app.asar')
Check ($t.Size -eq 10070 -and $t.H16 -eq 'ba544fc356c59987') ('hook = v2b after deploy (' + $t.Size + ' B)')
Check (Test-Path (Join-Path $res 'app.asar.bak')) 'app.asar.bak created'
if (Test-Path (Join-Path $res 'app.asar.bak')) { Check ((Get-Item (Join-Path $res 'app.asar.bak')).Length -eq 390786) 'app.asar.bak = 390786 B (stock)' }
Check (Test-Path (Join-Path $res 'app.bak\launch.dist.js')) 'app.bak\ created'
if (Test-Path (Join-Path $res 'app.bak\launch.dist.js')) {
  $l16 = (Get-Hex ([IO.File]::ReadAllBytes((Join-Path $res 'app.bak\launch.dist.js')))).Substring(0,16)
  Check ($l16 -eq '3ec9df885d96feaa') 'app.bak\loader = stock'
}

# --- step 2: repeat deploy ---
Write-Host ''
Write-Host '[2] repeat deploy (rebuild from app.bak)'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $deploy -TyporaPath $sb
Check ($LASTEXITCODE -eq 0) 'deploy exit code 0'
$t = Hook-Of (Join-Path $res 'app.asar')
Check ($t.Size -eq 10070 -and $t.H16 -eq 'ba544fc356c59987') ('hook = v2b after repeat (' + $t.Size + ' B)')

# --- step 3: rollback to v1 ---
Write-Host ''
Write-Host '[3] rollback to v1 hook'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $deploy -TyporaPath $sb -HookFile $hookV1
Check ($LASTEXITCODE -eq 0) 'deploy exit code 0'
$t = Hook-Of (Join-Path $res 'app.asar')
Check ($t.Size -eq 8216 -and $t.H16 -eq 'e616232d646d4f2d') ('hook = v1 after rollback (' + $t.Size + ' B)')

# --- step 4: restore official ---
Write-Host ''
Write-Host '[4] restore official'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $restore -TyporaPath $sb
Check ($LASTEXITCODE -eq 0) 'restore exit code 0'
$t = Hook-Of (Join-Path $res 'app.asar')
Check ($t.Size -eq 1383 -and $t.H16 -eq '3ec9df885d96feaa') ('stock after restore (' + $t.Size + ' B)')
Check (Test-Path (Join-Path $res 'app.asar.hooked.bak')) 'app.asar.hooked.bak saved'

Write-Host ''
Write-Host ('== RESULT: ' + $script:pass + ' passed, ' + $script:fail + ' failed ==')
Write-Host 'note: a running Typora was closed by the deploy step; reopen it manually if needed.'
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
