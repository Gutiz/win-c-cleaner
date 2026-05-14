# win-c-cleaner

Windows 10 / 11 通用 C 盘清理 Skill —— 按「风险低 → 收益大」八阶段流程释放系统盘空间，预计可回收 **25–35 GB**。

仓库本身是一个 **Claude Skill**：包含一份 `SKILL.md` 指导文件加一组 PowerShell 脚本。Skill 可被 Claude Code / Claude Desktop / Anthropic Agent SDK 等支持 Skills 协议的客户端加载并自动触发。

---

## 功能概览

| 阶段 | 操作 | 预计耗时 | 预计收益 | 风险 |
|------|------|---------|---------|------|
| 1 | 系统临时文件 / 缓存 / 回收站 / 崩溃转储 | 5 min | 3–8 GB | 极低 |
| 2 | 关闭休眠 (`hiberfil.sys`) + 缩小虚拟内存 | 2 min | 8–10 GB | 极低 |
| 3 | DISM 清理 WinSxS 组件存储 | 10–20 min | 2–3 GB | 极低 |
| 4 | 卸载 UWP 垃圾应用（电脑管家、Widgets、Bing News 等） | 5 min | 1–1.5 GB | 低 |
| 5 | 移动大型 UWP 应用到非系统盘 | 5 min | 1+ GB | 极低 |
| 6 | 删除 `DriverStore` 中的重复旧驱动（分批） | 20–30 min | 3–5 GB | 中 |
| 7 | 卸载 OEM 预装软件（Dell / Lenovo / HP / ASUS / Acer / 试用杀软等） | 5 min | 0.5–1 GB | 中 |
| 8 | 删除 `C:\Recovery\Customizations\*.ppkg` 出厂预装包 | 2 min | 1–6 GB | 中（必须备份） |

**安全特性**：
- 全程要求管理员 PowerShell + Win10/11 自检
- 关键删除经过路径白名单 (`Test-SafePath`)，越界路径自动拒绝
- 阶段 1 默认 dry-run，需 `-Execute` 才真删
- 阶段 3 `/ResetBase`、阶段 6 删驱动、阶段 8 删 ppkg 都要求显式参数 + 二次确认
- 阶段 6 自动从删除清单剔除 `ntprint.inf` / `prnms*.inf`（系统打印机驱动，pnputil 删不掉）
- 阶段 8 强制 `-BackupDir` 指向非系统盘，复制+大小校验通过才删除

---

## 仓库结构

```
.
├── LICENSE
├── README.md                              ← 你正在看
└── skills/
    └── win-c-cleaner/
        ├── SKILL.md                       # Skill 触发说明 + 行为规约 + 8 阶段手册
        └── scripts/
            ├── _Common.ps1                # 公共：提权 / 系统校验 / 白名单删除 / 报告
            ├── Get-DiskReport.ps1         # before/after 磁盘报告
            ├── Get-AppDataTopConsumers.ps1# AppData Local / Roaming Top 15
            ├── Get-DuplicateDrivers.ps1   # 重复驱动扫描，输出 CSV + 待启用脚本
            ├── Invoke-Stage1-TempClean.ps1
            ├── Invoke-Stage2-HiberPagefile.ps1
            ├── Invoke-Stage3-DismCleanup.ps1
            ├── Invoke-Stage4-UwpBloat.ps1
            ├── Invoke-Stage5-MoveApps.ps1
            ├── Invoke-Stage6-DriverCleanup.ps1
            ├── Invoke-Stage7-OemBloat.ps1
            ├── Invoke-Stage8-RemovePpkg.ps1
            └── Clean-All.ps1              # 编排阶段 1–5，提示 6–8
```

---

## 安装

### 方式 A：作为 Claude Skill 使用（推荐）

#### Claude Code（CLI / 桌面 / VS Code 扩展）

把 `skills/win-c-cleaner/` 拷到本地 skills 目录：

```powershell
# Windows
git clone https://github.com/Gutiz/win-c-cleaner.git
$dst = "$env:USERPROFILE\.claude\skills\win-c-cleaner"
New-Item -ItemType Directory -Path $dst -Force | Out-Null
Copy-Item -Path .\win-c-cleaner\skills\win-c-cleaner\* -Destination $dst -Recurse -Force
```

```bash
# macOS / Linux（用于跨机管理 Skill；脚本仍需在 Windows 执行）
git clone https://github.com/Gutiz/win-c-cleaner.git
mkdir -p ~/.claude/skills
cp -r win-c-cleaner/skills/win-c-cleaner ~/.claude/skills/
```

也可放在项目级目录 `<project>/.claude/skills/win-c-cleaner/` 仅在该项目启用。

打开 Claude Code 后直接说 **"清理 C 盘"** / **"C drive cleanup"** 即可触发。

#### Claude Desktop App

在 Claude Desktop 中：`Settings → Skills → Add Skill → 选择 skills/win-c-cleaner 目录`，启用后在对话里使用即可。

#### Claude Agent SDK（Python / TypeScript）

```python
from claude_agent_sdk import ClaudeAgentOptions, query

options = ClaudeAgentOptions(
    skills_dirs=["./skills"],            # 指向仓库的 skills/
    allowed_tools=["Bash", "Read", "Write", "Edit"],
)
async for msg in query(prompt="清理 Windows C 盘", options=options):
    print(msg)
```

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

for await (const msg of query({
  prompt: "清理 Windows C 盘",
  options: {
    skillsDirs: ["./skills"],
    allowedTools: ["Bash", "Read", "Write", "Edit"],
  },
})) {
  console.log(msg);
}
```

### 方式 B：直接运行脚本（不通过 Agent）

```powershell
# 1. 克隆
git clone https://github.com/Gutiz/win-c-cleaner.git
cd win-c-cleaner\skills\win-c-cleaner\scripts

# 2. 以管理员身份运行 PowerShell，允许本地脚本
Set-ExecutionPolicy -Scope Process Bypass

# 3. 报告 + 编排器（阶段 1–5 交互式）
.\Get-DiskReport.ps1
.\Clean-All.ps1
```

---

## 使用示例

### 通过 Claude 触发

> **你**：我的 C 盘只剩 10 GB，帮我清理一下
>
> **Claude**：（自动加载 `win-c-cleaner` skill，运行 `Get-DiskReport.ps1` 拿基线，然后按阶段问你确认）

### 单独运行某一阶段

```powershell
# 阶段 1：先 dry-run 看看会删什么
.\Invoke-Stage1-TempClean.ps1            # 预演
.\Invoke-Stage1-TempClean.ps1 -Execute   # 实际清理

# 阶段 2：关闭休眠（释放 hiberfil.sys）
.\Invoke-Stage2-HiberPagefile.ps1 -DisableHibernation

# 阶段 3：DISM 清理 WinSxS（不带 -ResetBase 较安全）
.\Invoke-Stage3-DismCleanup.ps1

# 阶段 4：卸载 UWP 垃圾
.\Invoke-Stage4-UwpBloat.ps1 -DryRun         # 先看匹配到哪些
.\Invoke-Stage4-UwpBloat.ps1 -AggressiveList # 含 Xbox/Bing 等

# 阶段 5：列出可移动的大型 UWP 应用，打开设置页
.\Invoke-Stage5-MoveApps.ps1 -TargetDrive D:

# 阶段 6：重复驱动（分批，每批重启验证）
.\Get-DuplicateDrivers.ps1
.\Invoke-Stage6-DriverCleanup.ps1 -ScriptPath .\delete-old-drivers.ps1 -Batch Display
.\Invoke-Stage6-DriverCleanup.ps1 -ScriptPath .\delete-old-drivers.ps1 -Batch Display -Execute

# 阶段 7：OEM 预装
.\Invoke-Stage7-OemBloat.ps1
.\Invoke-Stage7-OemBloat.ps1 -IncludeRiskyFunctionKeys   # 也显示影响 Fn 键的

# 阶段 8：删 OEM ppkg（必须带备份目录）
.\Invoke-Stage8-RemovePpkg.ps1 -BackupDir D:\Backup-OEM-ppkg
```

---

## 推荐执行节奏

- **第 1 天**：阶段 1–5（约 30 分钟，全是极低风险，省 15+ GB）
- **第 2 天**：阶段 6 第 1 批（显卡驱动）→ 重启 → 用一晚验证
- **第 3 天**：阶段 6 第 2 批（蓝牙）+ 阶段 7
- **一周后** 一切正常：阶段 8（删 ppkg）

---

## 支持的 Agent 工具 / 客户端

此 Skill 遵循 Anthropic 官方 Skills 规范（`SKILL.md` + YAML frontmatter），可被以下工具加载：

| 工具 | 加载方式 | 说明 |
|------|---------|------|
| **Claude Code CLI** | `~/.claude/skills/` 或 `<project>/.claude/skills/` | 用户级 / 项目级两种作用域 |
| **Claude Code（Web）** | 仓库内 `skills/` 目录自动发现 | 需结合 SessionStart hook |
| **Claude Desktop** | Settings → Skills → Add Skill | 桌面端 |
| **Claude VS Code 扩展** | 同 Claude Code CLI | |
| **Claude Agent SDK (Python)** | `ClaudeAgentOptions(skills_dirs=[...])` | `pip install claude-agent-sdk` |
| **Claude Agent SDK (TypeScript)** | `query({ options: { skillsDirs: [...] } })` | `npm i @anthropic-ai/claude-agent-sdk` |
| **Anthropic API（Skills beta）** | 通过 `skills` 参数注入 | 需具备 Skills 权限 |

Skill 内的脚本调用了 `Bash`、`Read`、`Write`、`Edit` 等基础工具，没有依赖外部 MCP 服务器，可与任何 Anthropic 默认工具集配合使用。

### 运行时要求

- **OS**：Windows 10（10.0.19041+）/ Windows 11
- **Shell**：PowerShell 5.1（系统自带）或 PowerShell 7+
- **权限**：必须是管理员 PowerShell
- **可选**：`winget`（阶段 7 优先使用，缺失会回退到 MSI/InstallShield 静默卸载）
- 阶段 5 / 8 推荐有第二块盘（D: / E: / 移动盘）做迁移和备份目标

---

## 触发关键词（中英）

Skill 通过 `SKILL.md` frontmatter 中的描述自动匹配下列触发词：

- **中文**：C 盘清理、清理 C 盘、系统盘满了、系统盘没空间、Windows 磁盘清理、删除休眠文件、缩虚拟内存、WinSxS 清理、Windows.old
- **English**：free up C drive, clean C drive, Windows disk cleanup, WinSxS bloat, Windows.old, hiberfil.sys, pagefile

非 Windows 系统（macOS / Linux）会话中 Claude 不会触发该 Skill。

---

## 应急回滚

| 操作 | 恢复方法 |
|------|---------|
| 驱动删错了 | 设备管理器 → 右键设备 → 更新驱动 → 自动搜索 |
| 关了休眠想恢复 | `powercfg /h on` |
| Pagefile 调小后系统变慢 | 改回「自动管理所有驱动器的分页文件大小」 |
| UWP 误删 | Microsoft Store 搜索重装 |
| WinSxS 清得太狠 | 无法回滚，仅影响「卸载历史更新」 |
| 删了 ppkg 后悔 | 从 `-BackupDir` 拷回 `C:\Recovery\Customizations\` |

---

## 贡献

欢迎 Issue / PR：
- 增加其他 OEM 厂商的预装清单（阶段 7）
- 增加更多 UWP 垃圾包匹配模式（阶段 4）
- 多语言 (`SKILL.md` 触发词扩展)

---

## License

[MIT](./LICENSE)
