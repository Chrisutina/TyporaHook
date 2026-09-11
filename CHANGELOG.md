# Changelog

本文件记录 TyporaHook 工程包的全部变更。版本号：`主.次.修订`。

## v2.2.0 — 2026-09-12 —— 升级适配分析（analyze）

- 🔭 新增 `tools/analyze-version.ps1` + `tools/analyze.cmd` —— 把（升级后的）新 asar 与参照原版对比：
  成员结构 / 加载器文本 diff / 字节码哈希+内嵌字符串+定时器常数探测（530469 的多编码二进制搜索）/ 版本号，
  自动判定差异级别 **L1~L4** 并给出方案：
  - L1 仅外围变化 → **方案 A**：直接 `deploy.cmd`
  - L2 加载器变 / L3 字节码变 → **方案 B**：沙盒演练 + 部署 + 调参/观察
  - L4 大变 → **方案 C**：暂缓，先人工评估（报告含全部差异清单）
- 🎛 `-Retune`：从 hook 日志实证扫描 ≥4 分钟且未被压制的定时器，必要时自动生成
  `hook/launch.dist.tuned-<时间戳>.js`（`-Apply` 一键部署）；已被压制窗口覆盖的值自动排除
- 🧪 `test-all.ps1` 增加 analyze 冒烟断言（共 15 项）
- 🖱️ `analyze.cmd` 双击即用：分析后可选 部署 / 调参 / 打开报告 / 沙盒自测
- 📄 分析报告归档到 `_reports\analyze-<时间戳>.md`
- 🌐 仓库托管至 GitHub：https://github.com/Chrisutina/TyporaHook（2026-09-12）
- 🐛 修复记录：含中文 .ps1 必须带 UTF-8 BOM（PS5.1 无 BOM 按 ANSI 解析）；探针计数 `@()` 包装坑；历史日志候选误报

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
