<#  TyporaHook analyze-version.ps1 (v2.3.0)
    - Version-diff analyzer: compares a (new) app.asar against the reference stock asar
      (structure / loader text / bytecode hash+strings+timer-constant / package.json)
      and recommends a scheme (A green / B yellow / C red).
    - Timer retuner (-Retune): scans the hook log for real >=4min timers and generates
      a tuned hook file when the suppression window needs adjusting.

    Note: .jsc is a V8 bytecode cache (not encryption); it is compared by size / hash /
    embedded strings / known timer-constant encodings.

    Usage:
      powershell -File analyze-version.ps1                    (interactive: analyze + menu)
      powershell -File analyze-version.ps1 -Asar <file> [-Ref <file>] [-Quiet]
      powershell -File analyze-version.ps1 -Retune [-Apply]
#>
param(
  [string]$Asar = "",
  [string]$Ref  = "",
  [switch]$Retune,
  [switch]$Apply,
  [switch]$Quiet
)
$ErrorActionPreference = 'Continue'
$Root = Split-Path $PSScriptRoot -Parent
$Ver  = '2.3.0'
$KnownHooks = @{ 'ba544fc356c59987' = 'v2b (current)'; 'e616232d646d4f2d' = 'v1 (DreamNya)' }
$TimerRef = 530469

function Get-Hex($bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLower()
}
function Read-Asar($path) {
  $b = [IO.File]::ReadAllBytes($path)
  $hl = [System.BitConverter]::ToUInt32($b, 4)
  $jl = [System.BitConverter]::ToInt32($b, 12)
  $obj = ([Text.Encoding]::UTF8.GetString($b, 16, $jl) | ConvertFrom-Json)
  return @{ Bytes = $b; Base = (8 + $hl); Files = $obj.files }
}
function Get-MemberBytes($info, $name) {
  $p = $info.Files.PSObject.Properties[$name]
  if (-not $p) { return $null }
  $n = $p.Value
  $s = $info.Base + [int]$n.offset
  return $info.Bytes[$s..($s + $n.size - 1)]
}
function To-Latin($bytes) { [Text.Encoding]::GetEncoding(28591).GetString($bytes) }
function Find-Hits($bytes, $needle) {
  $t = To-Latin $bytes; $p = To-Latin $needle
  $res = New-Object System.Collections.Generic.List[int]
  $i = 0
  while ($true) {
    $i = $t.IndexOf($p, $i, [System.StringComparison]::Ordinal)
    if ($i -lt 0) { break }
    $res.Add($i)
    $i++
    if ($res.Count -ge 50) { break }
  }
  return ,$res
}
function Enc-Uleb([uint64]$u) {
  $out = New-Object System.Collections.Generic.List[byte]
  do {
    $b = [byte]($u -band 0x7F)
    $u = $u -shr 7
    if ($u -ne 0) { $b = $b -bor 0x80 }
    $out.Add($b)
  } while ($u -ne 0)
  return $out.ToArray()
}
function Enc-Zig([int64]$v) {
  $z = [uint64](($v -shl 1) -bxor ($v -shr 63))
  return Enc-Uleb $z
}
function Get-StrSet($bytes) {
  $t = To-Latin $bytes
  $s = New-Object System.Collections.Generic.HashSet[string]
  foreach ($m in [regex]::Matches($t, '[\x20-\x7E]{6,}')) { $null = $s.Add($m.Value) }
  return ,$s
}
function Find-TyporaPath {
  $p = Get-Process Typora -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
  if ($p) { $d = Split-Path $p.Path -Parent; if (Test-Path (Join-Path $d 'resources\app.asar')) { return $d } }
  foreach ($rk in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Typora.exe','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Typora.exe')) {
    $r = Get-ItemProperty $rk -ErrorAction SilentlyContinue
    if ($r -and $r.'(default)') { $d = Split-Path $r.'(default)' -Parent; if (Test-Path (Join-Path $d 'resources\app.asar')) { return $d } }
  }
  foreach ($d in @("$env:ProgramFiles\Typora", "${env:ProgramFiles(x86)}\Typora", "$env:LOCALAPPDATA\Programs\Typora", "D:\Typora")) {
    if (Test-Path (Join-Path $d 'resources\app.asar')) { return $d }
  }
  return $null
}

$rep = New-Object System.Collections.Generic.List[string]
function Say($s, [switch]$Force) {
  $rep.Add($s) | Out-Null
  if ((-not $Quiet) -or $Force) { Write-Host $s }
}

function Invoke-Retune {
  Write-Host '== timer retune (empirical) =='
  $log = Join-Path $env:TEMP 'Typora_Hook_Log.txt'
  if (-not (Test-Path $log)) { Write-Host ('no hook log at ' + $log + ' - deploy the hook and boot Typora once first.'); return }
  $tail = Get-Content -LiteralPath $log -Tail 6000 -ErrorAction SilentlyContinue
  $supp = @{}; $cand = @{}
  foreach ($ln in $tail) {
    if ($ln -match 'TIMER-SUPPRESS .*delay=(\d+)') {
      $dv = [int]$matches[1]
      if (-not $supp.ContainsKey($dv)) { $supp[$dv] = 0 }
      $supp[$dv]++
    } elseif ($ln -match 'TIMER (?:setTimeout|setInterval) delay=(\d+)') {
      $dv = [int]$matches[1]
      if ($dv -ge 240000) {
        if (-not $cand.ContainsKey($dv)) { $cand[$dv] = 0 }
        $cand[$dv]++
      }
    }
  }
  foreach ($k in @($supp.Keys)) { if ($cand.ContainsKey($k)) { $cand.Remove($k) } }
  if ($supp.Count -gt 0) { Write-Host ('suppressed (already in window): ' + (($supp.Keys | Sort-Object) -join ', ')) }
  else { Write-Host 'suppressed: none in log' }
  if ($cand.Count -eq 0) {
    Write-Host 'candidates (>=4min, not suppressed): none'
    Write-Host 'VERDICT: no window change needed (or the hook is not instrumented).'
    return
  }
  Write-Host 'candidates (>=4min, not suppressed):'
  foreach ($k in ($cand.Keys | Sort-Object)) { Write-Host ('  ' + $k + ' ms  x' + $cand[$k]) }
  $vals = @($cand.Keys | Sort-Object)
  $low = $vals[0] - 60000; $high = $vals[-1] + 60000
  if (($high - $low) -gt 240000) {
    Write-Host ('window spread too wide (' + ($high - $low) + ' ms); choosing candidate closest to ' + $TimerRef + ' for auto-pick.')
    $best = $vals | Sort-Object { [Math]::Abs($_ - $TimerRef) } | Select-Object -First 1
    $low = $best - 60000; $high = $best + 60000
  }
  if ($low -lt 60000) { $low = 60000 }
  Write-Host ('recommended window: [' + $low + ', ' + $high + '] ms')
  $hookPath = Join-Path $Root 'hook\launch.dist.js'
  $txt = [IO.File]::ReadAllText($hookPath)
  $old = 'ms>=500000&&ms<=560000'
  $cnt = ([regex]::Matches($txt, [regex]::Escape($old))).Count
  if ($cnt -ne 1) { Write-Host ('X cannot auto-patch: found ' + $cnt + ' occurrences of the suppression condition (expect exactly 1).'); return }
  $new = $txt.Replace($old, ('ms>=' + $low + '&&ms<=' + $high))
  $out = Join-Path $Root ('hook\launch.dist.tuned-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.js')
  [IO.File]::WriteAllText($out, $new, (New-Object Text.UTF8Encoding($false)))
  $nh = (Get-Hex ([IO.File]::ReadAllBytes($out))).Substring(0,16)
  Write-Host ('tuned hook : ' + $out)
  Write-Host ('sha256(16) : ' + $nh + '   size ' + (Get-Item $out).Length + ' B')
  Write-Host ('deploy     : powershell -File "' + (Join-Path $PSScriptRoot 'deploy.ps1') + '" -HookFile "' + $out + '"')
  if ($Apply) {
    Write-Host '-- applying (deploy with tuned hook + restart Typora)...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'deploy.ps1') -HookFile $out -Restart
    Write-Host ('-- deploy exit: ' + $LASTEXITCODE)
  } else {
    Write-Host '-- not applied. Re-run with -Apply to deploy the tuned hook, or run the command above.'
  }
}

if ($Retune) { Invoke-Retune; exit 0 }

try {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  if (-not $Ref) { $Ref = Join-Path $Root 'payload\app.asar.stock-1.14.9.bak' }
  if (-not $Asar) {
    $tp = Find-TyporaPath
    if ($tp) { $Asar = Join-Path $tp 'resources\app.asar' } else { Write-Host 'X Typora not found and no -Asar given.'; exit 2 }
  }
  if (-not (Test-Path $Asar)) { Write-Host ('X asar not found: ' + $Asar); exit 2 }
  if (-not (Test-Path $Ref))  { Write-Host ('X reference not found: ' + $Ref); exit 2 }

  $tg = Read-Asar $Asar
  $rf = Read-Asar $Ref
  $tgFull = Get-Hex $tg.Bytes; $rfFull = Get-Hex $rf.Bytes

  Say ('== TyporaHook analyze v' + $Ver + ' ==')
  Say ('target : ' + $Asar)
  Say ('         ' + $tg.Bytes.Length + ' B  sha256 ' + $tgFull.Substring(0,16) + '...')
  Say ('ref    : ' + $Ref)
  Say ('         ' + $rf.Bytes.Length + ' B  sha256 ' + $rfFull.Substring(0,16) + '...')
  Say 'note   : .jsc is a V8 bytecode cache, not encryption; compared by size/hash/strings/timer-constant.'

  if ($tgFull -eq $rfFull) {
    Say ''
    Say '== RESULT: IDENTICAL - target equals the reference stock asar ==' -Force
    New-Item -ItemType Directory (Join-Path $Root '_reports') -Force | Out-Null
    $rp = Join-Path $Root ('_reports\analyze-' + $stamp + '.md')
    ($rep -join "`n") | Set-Content -Path $rp -Encoding UTF8
    Say ('report : ' + $rp)
    exit 0
  }

  # --- members ---
  $rfNames = @($rf.Files.PSObject.Properties.Name | Sort-Object)
  $tgNames = @($tg.Files.PSObject.Properties.Name | Sort-Object)
  $membersSame = (($rfNames -join ',') -eq ($tgNames -join ','))
  Say ''
  Say '== members =='
  foreach ($n in (@($rfNames + $tgNames) | Sort-Object -Unique)) {
    $re = $rf.Files.PSObject.Properties[$n]; $te = $tg.Files.PSObject.Properties[$n]
    $rs = if ($re) { '' + $re.Value.size + ' B @' + $re.Value.offset } else { '(absent)' }
    $ts = if ($te) { '' + $te.Value.size + ' B @' + $te.Value.offset } else { '(absent)' }
    Say ('  ' + $n.PadRight(24) + ' target: ' + $ts.PadRight(18) + ' ref: ' + $rs)
  }
  if (-not $membersSame) { Say '  !! member list differs (structure change)' }

  # --- loader ---
  $refL = Get-MemberBytes $rf 'launch.dist.js'
  $tgL  = Get-MemberBytes $tg 'launch.dist.js'
  Say ''
  Say '== loader (launch.dist.js) =='
  if (-not $tgL) { Say '  !! target has no launch.dist.js' }
  else {
    $refLH = (Get-Hex $refL).Substring(0,16); $tgLH = (Get-Hex $tgL).Substring(0,16)
    $known = $KnownHooks[$tgLH]
    $hookedTag = if ($known) { ' -> ' + $known } elseif ($tgL.Length -ge 4096) { ' -> looks HOOKED (unknown build)' } else { '' }
    Say ('  target: ' + $tgL.Length + ' B  sha16 ' + $tgLH + $hookedTag)
    Say ('  ref   : ' + $refL.Length + ' B  sha16 ' + $refLH)
    $loaderSame = ($refLH -eq $tgLH)
    if (-not $loaderSame -and ($tgL.Length -lt 4096)) {
      $aL = To-Latin $refL; $bL = To-Latin $tgL
      $minLen = [Math]::Min($aL.Length, $bL.Length)
      $pre = 0; while ($pre -lt $minLen -and $aL[$pre] -eq $bL[$pre]) { $pre++ }
      $suf = 0; while ($suf -lt ($minLen - $pre) -and $aL[$aL.Length - 1 - $suf] -eq $bL[$bL.Length - 1 - $suf]) { $suf++ }
      $rm = $aL.Substring($pre, [Math]::Max(0, $aL.Length - $pre - $suf)).Replace("`r",'').Replace("`n",'\n')
      $tm = $bL.Substring($pre, [Math]::Max(0, $bL.Length - $pre - $suf)).Replace("`r",'').Replace("`n",'\n')
      Say ('  diff  : common-prefix ' + $pre + ' chars, common-suffix ' + $suf + ' chars, changed-middle ' + $rm.Length + ' vs ' + $tm.Length + ' chars')
      if ($rm.Length -gt 0) { Say ('  ref-mid   : ' + $rm.Substring(0, [Math]::Min(400, $rm.Length))) }
      if ($tm.Length -gt 0) { Say ('  target-mid: ' + $tm.Substring(0, [Math]::Min(400, $tm.Length))) }
    }
  }

  # --- bytecode ---
  $refJ = Get-MemberBytes $rf 'atom.compiled.dist.jsc'
  $tgJ  = Get-MemberBytes $tg 'atom.compiled.dist.jsc'
  Say ''
  Say '== bytecode (atom.compiled.dist.jsc) =='
  if (-not $refJ -or -not $tgJ) { Say '  !! jsc missing on one side' }
  else {
    $refJH = (Get-Hex $refJ).Substring(0,16); $tgJH = (Get-Hex $tgJ).Substring(0,16)
    $jscSame = ($refJH -eq $tgJH)
    Say ('  target: ' + $tgJ.Length + ' B  sha16 ' + $tgJH)
    Say ('  ref   : ' + $refJ.Length + ' B  sha16 ' + $refJH)
    Say ('  same  : ' + $jscSame)
    $sr = Get-StrSet $refJ; $st = Get-StrSet $tgJ
    $added = @($st | Where-Object { -not $sr.Contains($_) })
    $removed = @($sr | Where-Object { -not $st.Contains($_) })
    Say ('  strings: added ' + $added.Count + ', removed ' + $removed.Count)
    $i = 0
    foreach ($s in $added) { if ($i -ge 15) { break }; Say ('    + ' + $s.Substring(0, [Math]::Min(90, $s.Length))); $i++ }
    $i = 0
    foreach ($s in $removed) { if ($i -ge 15) { break }; Say ('    - ' + $s.Substring(0, [Math]::Min(90, $s.Length))); $i++ }
    Say ('  timer-constant probe (' + $TimerRef + ' ms):')
    $needles = @(
      @{ n = 'int32-le';      b = [BitConverter]::GetBytes([int32]$TimerRef) },
      @{ n = 'int32-be';      b = $( $t = [BitConverter]::GetBytes([int32]$TimerRef); [Array]::Reverse($t); $t ) },
      @{ n = 'float64-le';    b = [BitConverter]::GetBytes([double]$TimerRef) },
      @{ n = 'uleb128';       b = (Enc-Uleb ([uint64]$TimerRef)) },
      @{ n = 'uleb128-zigzag'; b = (Enc-Zig ([int64]$TimerRef)) }
    )
    foreach ($nd in $needles) {
      $rHit = Find-Hits $refJ $nd.b
      $tHit = Find-Hits $tgJ $nd.b
      $rh = $rHit.Count
      $th = $tHit.Count
      $hexs = (($nd.b | ForEach-Object { $_.ToString('X2') }) -join ' ')
      Say ('    [' + $nd.n.PadRight(15) + '] ' + $hexs.PadRight(24) + ' ref=' + $rh + '  target=' + $th)
    }
  }

  # --- package.json ---
  $refP = Get-MemberBytes $rf 'package.json'
  $tgP  = Get-MemberBytes $tg 'package.json'
  $refV = ''; $tgV = ''
  if ($refP) { try { $refV = ([Text.Encoding]::UTF8.GetString($refP) | ConvertFrom-Json).version } catch {} }
  if ($tgP)  { try { $tgV  = ([Text.Encoding]::UTF8.GetString($tgP)  | ConvertFrom-Json).version } catch {} }
  Say ''
  Say ('== package.json: target=' + $tgV + '  ref=' + $refV + ' ==')

  # --- verdict ---
  $tgHooked = $false
  if ($tgL -and (($tgL.Length -ge 4096) -or ($KnownHooks[(Get-Hex $tgL).Substring(0,16)]))) { $tgHooked = $true }
  $level = 'L4'
  if ($tgHooked) { $level = 'DEPLOYED' }
  elseif ($jscSame -and $loaderSame -and $membersSame) { $level = 'L1' }
  elseif ($jscSame -and -not $loaderSame) { $level = 'L2' }
  elseif ((-not $jscSame) -and $loaderSame -and $membersSame) { $level = 'L3' }
  else { $level = 'L4' }

  Say ''
  Say '== 方案 (schemes) =='
  Say '  [方案 A · 绿灯] 直接部署: tools\deploy.cmd                     (适用 L1)'
  Say '  [方案 B · 黄灯] 沙盒演练 -> 部署 -> 调参/观察: 见下方命令组      (适用 L2/L3)'
  Say '  [方案 C · 红灯] 暂缓部署, 先人工评估差异清单                    (适用 L4)'
  Say ''
  switch ($level) {
    'L1' { Say '  推荐: 方案 A —— 差异仅在外围/元数据, 直接部署。'; Say '        命令: tools\deploy.cmd   (跑完 tools\verify.ps1 复核)' }
    'L2' { Say '  推荐: 方案 B —— 加载器有变化 (hook 内含旧加载器逻辑)。命令组:'
           Say ('    1) 保存新原版: copy "' + $Asar + '" "payload\app.asar.stock-' + $tgV + '.bak"')
           Say '    2) 沙盒试装: 把新 asar 拷到 tests\sandbox\FakeTypora\resources\app.asar, 再跑 tests\tools\deploy.ps1 -TyporaPath tests\sandbox\FakeTypora'
           Say '    3) 真机部署: tools\deploy.cmd'
           Say '    4) 启动一次 + 跑 tools\verify.ps1 + 观察 hook 日志 15 分钟' }
    'L3' { Say '  推荐: 方案 B —— 字节码有变化 (530s 定时器假设需复核)。命令组:'
           Say '    1) 部署: tools\deploy.cmd'
           Say '    2) 启动 Typora 一次, 然后: tools\analyze.cmd -Retune  (自动核对/生成调参 hook)'
           Say '    3) 观察 15 分钟: 无 typora.log "2nd" / hook 日志正常 = 适配完成' }
    'L4' { Say '  推荐: 方案 C —— 变化较大 (加载器与字节码/结构均有变)。先人工评估上方差异清单, 或等待 hook 适配更新。' }
    'DEPLOYED' { Say '  当前目标是"已部署 hook 的版本"(非原始包)。' 
           Say '  如需分析新版本: 等 Typora 更新覆盖 resources 后再跑; 或指定一个原始 app.asar: analyze.cmd -Asar <path>' }
  }

  New-Item -ItemType Directory (Join-Path $Root '_reports') -Force | Out-Null
  $rp = Join-Path $Root ('_reports\analyze-' + $stamp + '.md')
  ($rep -join "`n") | Set-Content -Path $rp -Encoding UTF8
  Say ''
  Say ('report : ' + $rp)
  Say ('== RESULT: ' + $level + ' ==') -Force

  if (($PSBoundParameters.Count -eq 0) -and [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected)) {
    while ($true) {
      Write-Host ''
      Write-Host '操作: [1] 部署 v2b   [2] 定时器调参(/retune)   [3] 打开报告   [4] 沙盒自测   [0] 退出'
      $c = Read-Host '选择'
      switch ($c) {
        '1' { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'deploy.ps1') }
        '2' { Invoke-Retune }
        '3' { Invoke-Item $rp }
        '4' { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-all.ps1') }
      }
      if ([string]::IsNullOrEmpty($c) -or $c -eq '0') { break }
    }
  }
  exit 0
} catch {
  Write-Host ('X ' + $_.Exception.Message)
  exit 1
}
