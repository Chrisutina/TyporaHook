# TyporaHook — Typora 离线激活 Hook · 工程包

> **版本 v2.3.0**（2026-09-14）· 内含 hook **v2b** · 零联网依赖：部署 / 还原 / 自测全部本地完成 · 仓库：https://github.com/Chrisutina/TyporaHook

把 2026-08 部署的 DreamNya 离线激活 hook，维护成一个"**可部署、可回滚、可自检、可自测、可打包**"的工程：不修改 Typora 原厂字节码（`atom.compiled.dist.jsc` 原封不动），只替换加载器（`launch.dist.js`）并重打包 `app.asar`；所有改动均可一键还原官方。

## ✨ 特性

- **工具箱菜单** `TyporaHook.cmd`：所有命令集中一个窗口、逐条带说明自选运行，跑完停留（推荐入口）
- **一键部署**：自动探测 Typora 安装路径（进程 / 注册表 / 快捷方式 / 常见目录），首次部署自动建立备份链，重建后自校验
- **一键还原**：`tools\restore.cmd` 把官方原版 `app.asar` 放回（当前版本另存为 `app.asar.hooked.bak`，有后悔药）
- **状态自检** `tools\verify.ps1`：hook 版本 / 备份链 / 注册表 / CDP 端口，一屏看健康度（只读）
- **沙盒自测** `tools\test-all.ps1`：部署 → 重复部署 → 回滚 → 还原 四连全自动（只在 `tests\sandbox` 内操作，不碰真机）
- **发布打包** `tools\build-release.ps1`：生成版本化 ZIP + SHA256
- **升级适配分析** `tools\analyze.cmd`：新版本 asar 对比 + 差异分级（L1~L4）+ 方案推荐；`-Retune` 从日志实证生成调参 hook
- **安全设计**：CDP 调试口默认关闭（`TYPORA_HOOK_DEBUG=1` 才开）、530 秒"掉激活"定时器压制、外部调试参数清除防御

## 🚀 快速开始

| 场景 | 操作 |
|---|---|
| 打开工具箱（推荐入口） | 双击根目录 `TyporaHook.cmd`，按编号选命令（每项跑完停住） |
| 部署 / Typora 升级后重装 | 菜单 `[2]`；或双击 `tools\deploy.cmd`（`-Check` 可先预览，`-Restart` 完事自动重启） |
| 升级适配分析（Typora 更新后第一步） | 菜单 `[4]`；或双击 `tools\analyze.cmd` |
| 状态自检（只读体检） | 菜单 `[1]`；脚本本体 `tools\verify.ps1` |
| 沙盒自测（不碰真机；会短暂关闭正在运行的 Typora） | 菜单 `[6]`；脚本本体 `tools\test-all.ps1` |
| 回滚到 v1 钩子 | 菜单 `[7]`（换回 DreamNya 原版钩子） |
| 完全还原官方 | 菜单 `[8]`；或双击 `tools\restore.cmd` |
| 打发布包 | 菜单 `[9]`；脚本本体 `tools\build-release.ps1` |

要求：Windows 10/11 + 系统自带 PowerShell 5.1（零外部依赖，不需要 Node）。

## 📁 目录结构

```
TyporaHook\
├─ TyporaHook.cmd · 工具箱菜单入口（双击）
├─ README.md / CHANGELOG.md / LICENSE.md / CHECKSUMS.sha256
├─ docs\    · 机制详解.md · 常见问题.md · 测试记录.md
├─ hook\    · launch.dist.js（v2b 当前）· launch.dist.orig.js（v1 原版备份）
├─ payload\ · app.asar.stock-1.14.9.bak（1.14.9 官方原版 asar 素材）
├─ tools\   · deploy / restore / verify / test-all / build-release / analyze / menu / analyze / menu
├─ tests\   · sandbox\FakeTypora（沙盒假安装）
└─ release\ · 发布产物（ZIP + .sha256）
```

## 🧬 版本与兼容

- 工程 **v2.3.0** = hook **v2b**（CDP 门控 + 530s 压制 + 插桩，sha256 `ba544fc3…`）+ 工具链
- 实测环境：**Typora 1.14.9**（Windows x64）；理论兼容 1.14.x；1.15+ 未验证（升级后先跑 `verify.ps1`，异常先 `restore.cmd`）
- 当前真机部署指纹：`D:\Typora\resources\app.asar` sha256 `1e426e57…`（2026-09-11）

## 🔒 安全设计（为什么可以放心用）

- **不动原厂字节码**：`atom.compiled.dist.jsc`（反调试逻辑所在）保持原样，只换加载器
- **CDP 默认关**：修掉了"任意本机进程可接管 Typora 主进程"的坑（v1 会无条件开 `remote-debugging-port=9223`）
- **530s 定时器压制**：修掉了"用久了掉激活、重启才好"的坑（Typora 每会话埋伏一个 530,469ms 定时器随机清许可证）
- **全程可逆**：备份链 `app.bak\` + `app.asar.bak` 完整保留；`restore.cmd` 秒回官方
- **零联网**：部署 / 还原 / 自测全部本地完成，不下载任何东西

## 📚 文档

- [docs/机制详解.md](docs/机制详解.md) — hook 逐段拆解、asar 格式、两个坑的修复原理
- [docs/常见问题.md](docs/常见问题.md) — 报错、升级、杀软、调试、还原 FAQ
- [docs/测试记录.md](docs/测试记录.md) — 三轮实机验证 + 沙盒四连 + 自动化回归

## ⚠️ 免责声明

本工程仅供**学习研究与本地环境维护**使用，不得用于商业用途或二次分发牟利。
hook 源自 DreamNya 的公开版本；**请支持正版**（Typora 官网正版授权）。
使用本工程所致一切后果由使用者自负。详见 `LICENSE.md`。
