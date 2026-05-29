# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [SemVer](https://semver.org/lang/zh-CN/)。

## [1.0.0] - 2026-05-14

首发版本：Windows 10/11 通用 C 盘清理 Skill。

### Added

- `skills/win-c-cleaner/SKILL.md`：Skill 触发说明 + 行为规约 + 8 阶段手册。
- 8 个独立 stage 脚本，可单独执行或通过 `Clean-All.ps1` 编排：
  - Stage 1 `Invoke-Stage1-TempClean.ps1` —— 临时文件 / 缓存 / 回收站 / 崩溃转储（默认 dry-run）
  - Stage 2 `Invoke-Stage2-HiberPagefile.ps1` —— `powercfg /h off` + `pagefile` 缩容
  - Stage 3 `Invoke-Stage3-DismCleanup.ps1` —— DISM WinSxS 组件清理（可选 `/ResetBase`）
  - Stage 4 `Invoke-Stage4-UwpBloat.ps1` —— UWP 垃圾应用卸载（含 `-AggressiveList`）
  - Stage 5 `Invoke-Stage5-MoveApps.ps1` —— 大型 UWP 应用迁移到其他盘
  - Stage 6 `Invoke-Stage6-DriverCleanup.ps1` + `Get-DuplicateDrivers.ps1` —— 重复驱动分批清理
  - Stage 7 `Invoke-Stage7-OemBloat.ps1` —— OEM 预装软件（Dell/Lenovo/HP/ASUS/Acer/试用杀软）
  - Stage 8 `Invoke-Stage8-RemovePpkg.ps1` —— OEM ppkg 强制备份后删除
- 辅助脚本：`Get-DiskReport.ps1`、`Get-AppDataTopConsumers.ps1`、`_Common.ps1`。
- 安全机制：管理员自检、Windows 10+ 自检、`Test-SafePath` 白名单、dry-run 默认、二次确认。
- 中英双语 README（`README.md` / `README.en.md`）。
- `.github/CODEOWNERS`、`.github/workflows/release-guard.yml`（branch-policy 工作流）、PR 模板。
- 分支策略：`feat/* → PR → release → PR → main`，release 和 main 受保护，禁止直接 push 与 force push。

### Security

- 删除操作均经过路径白名单校验，越界路径自动拒绝。
- Stage 3 `/ResetBase`、Stage 6 删驱动、Stage 8 删 ppkg 均要求显式参数 + 二次确认。
- Stage 8 强制 `-BackupDir` 指向非系统盘，复制+大小校验通过后才删除原文件。

### Notes

- 预计在 Win10/11 上典型可释放 **25–35 GB** 空间。
- 阶段 2/3/6 完整生效需重启。
- 阶段 5/8 推荐有第二块盘（D:/E:/移动盘）。

[1.0.0]: https://github.com/Gutiz/win-c-cleaner/releases/tag/v1.0.0
