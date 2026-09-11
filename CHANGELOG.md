# Changelog

本文件记录 TyporaHook 工程包的全部变更。版本号：`主.次.修订`。

## v2.1.0 — 2026-09-12 —— 工程化封版

- 📦 成建制：完整目录结构（docs / hook / payload / tools / tests / release）
- 📖 文档三件套：机制详解 / 常见问题 / 测试记录
- 🔍 新增 `tools/verify.ps1` —— 真机状态自检（hook 版本、备份链、注册表、CDP 9223 端口，只读）
- 🧪 新增 `tools/test-all.ps1` —— 沙盒自动化四连（部署 → 重复 → 回滚 → 还原），不碰真机
- 🚢 新增 `tools/build-release.ps1` —— 发布打包（ZIP + SHA256 + MANIFEST）
- 🧾 新增 `CHECKSUMS.sha256`（全工程指纹）与 `LICENSE.md`
- 本地 git 仓库（仅本地版本管理，不推送任何远程）
- hook 与工具本体无行为变更（仍为 v2b / u1 逻辑）

## v2.0b — 2026-09-11 —— 修复版（当前 hook 基线）

- **CDP 门控**：`remote-debugging-port=9223` 改为默认关闭（`TYPORA_HOOK_DEBUG=1` 开启）；非调试模式 `removeSwitch` 清外部调试参数
- **530s 压制**：拦截 [500000, 560000] ms 定时器（Typora 的二次校验 → 空回调），解决"用久了掉激活"
- **插桩**：启动 argv / appendSwitch / ≥60s 定时器记录（诊断用）
- v2a 事故修复：插桩自带独立 logger（原版 `log` 为块作用域 → ReferenceError 崩溃）
- 验证：R1 / R2 / R3 三轮 × 575s 全绿（无 `2nd`、无 9223 监听、注册表稳定）
- hook 指纹：sha256 `ba544fc356c59987d83702baa9f73829b784f2ed5666c8f523c040b5676ea74e`（10,070 B）

## v2.0a — 2026-09-11 —— 开发事故（未交付，留档）

- 首版插桩实现，部署后 Typora 启动崩溃（`ReferenceError: log is not defined`）→ 当日修复为 v2.0b

## u1 — 2026-09-11 —— 通用工具包（toolkit）

- deploy / restore 双脚本 + 沙盒四连演练通过；已并入本工程 `tools\`

## v1.0 — 2026-08-25 —— 初始部署

- DreamNya 离线激活 hook 首次部署（hook sha256 `e616232d646d4f2d0fd986093b0d0a9b0a48475e53c9042088b9d62078e479a1`，8,216 B）
- 原版素材：`app.asar.bak`（sha256 `d338ccbb58cb030b0adea2ebfd44fe10ee991955f0bd9d565c7d4f19e2ece1c8`，390,786 B）
