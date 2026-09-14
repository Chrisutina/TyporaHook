<#  TyporaHook 工具箱菜单 (v2.3.1)
    把工程里所有命令收进一个窗口：每条带用途说明、按编号选择运行。
    每个操作跑完都会停住等回车，窗口不会一闪而过。
    双击工程根目录的 TyporaHook.cmd 启动本菜单。
#>
$ErrorActionPreference = 'Continue'
$Root = Split-Path $PSScriptRoot -Parent
$hasTest = Test-Path (Join-Path $Root 'tools\test-all.ps1')
$hasPack = Test-Path (Join-Path $Root 'tools\build-release.ps1')

function Show-Menu {
  if (-not [Console]::IsOutputRedirected) { try { Clear-Host } catch {} }
  Write-Host '============================================================='
  Write-Host '    TyporaHook 工具箱 v2.3.1   （双击 TyporaHook.cmd 启动）'
  Write-Host '============================================================='
  Write-Host ''
  Write-Host '  [1] 状态自检        — hook / 备份链 / 注册表 / 9223 端口，一屏体检（只读）'
  Write-Host '  [2] 部署/重新部署   — 把 hook 注入 Typora（会先关掉 Typora；升级后用这个）'
  Write-Host '  [3] 部署预览        — 只检查不修改（-Check）'
  Write-Host '  [4] 升级适配分析    — 对比新版本 asar 给方案（进入分析菜单）'
  Write-Host '  [5] 定时器调参      — 从日志找新定时器，生成调参 hook（-Retune）'
  if ($hasTest) { Write-Host '  [6] 沙盒自测        — 部署→重复→回滚→还原 全自动四连（不碰真机）' }
  Write-Host ''
  Write-Host '  [7] 回滚到 v1 钩子  — 换回 8/25 的 DreamNya 原版钩子'
  Write-Host '  [8] 还原官方        — 一键回官方版（当前版另存为后悔药）'
  if ($hasPack) { Write-Host '  [9] 打发布包        — 生成 release\TyporaHook-v*.zip + SHA256' }
  Write-Host ''
  Write-Host '  [R] 打开 README        [D] 打开文档文件夹      [L] 看 hook 日志'
  Write-Host '  [O] 打开工程目录       [Q] 退出'
  Write-Host ''
}

function Invoke-Tool([string]$Desc, [string[]]$PSArgs) {
  Write-Host ''
  Write-Host ("—————— " + $Desc + " ——————")
  Write-Host ''
  & powershell.exe -NoProfile -ExecutionPolicy Bypass @PSArgs
  Write-Host ''
  Write-Host ("[上面命令退出码: " + $LASTEXITCODE + "]")
}

while ($true) {
  Show-Menu
  try { $c = Read-Host '请输入编号（1-9 / R / D / L / O / Q）' } catch { break }
  if ($null -eq $c) { break }
  $c = $c.Trim()
  if ($c -eq '') { continue }
  $quit = $false
  switch ($c.ToUpper()) {
    '1' { Invoke-Tool '状态自检（verify.ps1，只读）' @('-File', (Join-Path $Root 'tools\verify.ps1')) }
    '2' { Invoke-Tool '部署 v2b hook（会先关闭 Typora）' @('-File', (Join-Path $Root 'tools\deploy.ps1')) }
    '3' { Invoke-Tool '部署预览（-Check，不做任何修改）' @('-File', (Join-Path $Root 'tools\deploy.ps1'), '-Check') }
    '4' { Invoke-Tool '升级适配分析' @('-File', (Join-Path $Root 'tools\analyze-version.ps1')) }
    '5' { Invoke-Tool '定时器调参（-Retune）' @('-File', (Join-Path $Root 'tools\analyze-version.ps1'), '-Retune') }
    '6' { if ($hasTest) { Invoke-Tool '沙盒自测（test-all）' @('-File', (Join-Path $Root 'tools\test-all.ps1')) } else { Write-Host '此功能为开发者本地提供，未随仓库分发。' } }
    '7' { Invoke-Tool '回滚到 v1 钩子' @('-File', (Join-Path $Root 'tools\deploy.ps1'), '-HookFile', (Join-Path $Root 'hook\launch.dist.orig.js')) }
    '8' { Invoke-Tool '还原官方版' @('-File', (Join-Path $Root 'tools\restore-official.ps1')) }
    '9' { if ($hasPack) { Invoke-Tool '打发布包' @('-File', (Join-Path $Root 'tools\build-release.ps1')) } else { Write-Host '此功能为开发者本地提供，未随仓库分发。' } }
    'R' { Invoke-Item (Join-Path $Root 'README.md') }
    'D' { Invoke-Item (Join-Path $Root 'docs') }
    'L' {
      $log = Join-Path $env:TEMP 'Typora_Hook_Log.txt'
      if (Test-Path $log) { Invoke-Item $log } else { Write-Host 'hook 日志还没生成——先启动一次 Typora 再看。' }
    }
    'O' { Invoke-Item $Root }
    'Q' { $quit = $true }
    default { Write-Host ('无效输入: ' + $c + '（可用: 1-9 或 R/D/L/O/Q）') }
  }
  if ($quit) { break }
  Write-Host ''
  try { $null = Read-Host '按回车返回菜单（Ctrl+C 退出）' } catch { break }
}
