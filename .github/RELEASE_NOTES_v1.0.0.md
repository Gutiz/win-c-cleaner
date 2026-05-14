# win-c-cleaner v1.0.0

首个稳定版本 —— Windows 10/11 通用 C 盘清理 Claude Skill。

## 亮点

- **8 阶段流程**：从极低风险的临时文件清理 → 重复驱动 → OEM 预装包，按「风险低→收益大」顺序释放空间，预计回收 **25–35 GB**。
- **Claude Skill 标准结构**：`SKILL.md` + YAML frontmatter，支持 Claude Code（CLI / Web / Desktop / VS Code）、Claude Agent SDK（Python / TypeScript）、Anthropic API Skills beta。
- **安全设计**：管理员自检、Win10+ 自检、路径白名单、dry-run 默认、二次确认；Stage 8 强制非系统盘备份 + 大小校验。
- **中英双语文档**：完整安装、使用、回滚说明。
- **CI 守卫**：`branch-policy` 工作流防止意外破坏分支策略。

## 快速安装

```powershell
# Claude Code（Windows）
git clone https://github.com/Gutiz/win-c-cleaner.git
$dst = "$env:USERPROFILE\.claude\skills\win-c-cleaner"
New-Item -ItemType Directory -Path $dst -Force | Out-Null
Copy-Item .\win-c-cleaner\skills\win-c-cleaner\* $dst -Recurse -Force
```

之后对 Claude 说 **「清理 C 盘」** 或 **「free up C drive」** 即可触发。

## 直接运行（不通过 agent）

```powershell
# 管理员 PowerShell
Set-ExecutionPolicy -Scope Process Bypass
cd .\win-c-cleaner\skills\win-c-cleaner\scripts
.\Get-DiskReport.ps1
.\Clean-All.ps1
```

## 兼容性

- Windows 10（10.0.19041+）/ Windows 11
- PowerShell 5.1（系统自带）或 PowerShell 7+
- 必须管理员身份运行
- 可选：`winget`（Stage 7 优先用，缺失自动 fallback）

## 已知限制

- 阶段 5 UWP 应用迁移因 Windows API 限制需手动点击「移动」按钮，脚本会自动打开设置页。
- 阶段 6 / 7 / 8 不会自动批处理多项，每项单独确认。

## License

[MIT](./LICENSE)
