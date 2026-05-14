---
name: win-c-cleaner
description: Windows 10/11 通用 C 盘清理 skill。按 8 阶段（风险低→收益大）分批释放系统盘空间：临时文件、休眠/虚拟内存、DISM WinSxS、UWP 应用、移动大应用、重复驱动、OEM 软件、出厂预装包。预计释放 25-35 GB。在用户提到「C 盘清理 / 清理 C 盘 / 系统盘满了 / free up C drive / Windows 磁盘清理 / WinSxS / Windows.old / 删除休眠文件 / 缩虚拟内存」时使用。
---

# Windows C 盘通用清理 Skill（Win10/11）

按官方手册 8 阶段顺序操作，**风险低 → 收益大**，每阶段独立，做完确认无误再进下一个。整套做完通常可释放 **25-35 GB**。

## 触发条件

- 用户当前在 Windows 10 或 Windows 11 系统
- 用户希望释放 C 盘空间、降低系统盘占用、清理临时文件/缓存/驱动
- 不要在 Linux / macOS 会话中调用此 skill

## 运行前必查（assistant 必须确认）

1. **管理员 PowerShell**：所有阶段都要求管理员权限。脚本会自检，未提权直接退出。
2. **当前可用空间**：先跑 `scripts/Get-DiskReport.ps1`，记录 C 盘 before 数值。
3. **系统版本**：`Get-CimInstance Win32_OperatingSystem` 必须是 Win10（10.0.19041+）或 Win11。
4. **D 盘可选**：阶段 5/8 需要其他卷做迁移/备份；如无，跳过或改用外接盘。

## 阶段总览

| 阶段 | 操作 | 耗时 | 收益 | 风险 | 脚本 |
|------|------|------|------|------|------|
| 1 | 系统临时文件/缓存 | 5 min | 3-8 GB | 极低 | `Invoke-Stage1-TempClean.ps1` |
| 2 | 关休眠 + 缩虚拟内存 | 2 min | 8-10 GB | 极低 | `Invoke-Stage2-HiberPagefile.ps1` |
| 3 | DISM 清理 WinSxS | 10-20 min | 2-3 GB | 极低 | `Invoke-Stage3-DismCleanup.ps1` |
| 4 | 卸载 UWP 垃圾应用 | 5 min | 1-1.5 GB | 低 | `Invoke-Stage4-UwpBloat.ps1` |
| 5 | 移动大型应用到其他盘 | 5 min | 1+ GB | 极低 | `Invoke-Stage5-MoveApps.ps1` |
| 6 | 删除重复驱动 | 20-30 min | 3-5 GB | 中 | `Invoke-Stage6-DriverCleanup.ps1` |
| 7 | 卸载 OEM 预装软件 | 5 min | 0.5-1 GB | 中 | `Invoke-Stage7-OemBloat.ps1` |
| 8 | 删除 OEM 出厂预装包 | 2 min | 1-6 GB | 中（需备份） | `Invoke-Stage8-RemovePpkg.ps1` |

入口编排：`scripts/Clean-All.ps1`（按顺序提示，每阶段确认）。

---

## 阶段 1：临时文件 / 缓存（极低风险）

清理目标：
- `C:\Windows\Temp\*`
- `%TEMP%\*`、`%LOCALAPPDATA%\Temp\*`
- `C:\Windows\SoftwareDistribution\Download\*`（Windows Update 缓存，会停 `wuauserv` 再删再启）
- 回收站
- `thumbcache_*.db` 缩略图缓存
- `C:\Windows\Prefetch\*`
- `C:\ProgramData\Microsoft\Windows\WER\ReportQueue|ReportArchive`
- `C:\Windows\Minidump\*.dmp`、`C:\Windows\MEMORY.DMP`
- Delivery Optimization 缓存

可选 GUI 兜底：`Win+R → cleanmgr → 选 C 盘 → 清理系统文件 → 全选`。

脚本：`scripts/Invoke-Stage1-TempClean.ps1`（默认 `-WhatIf` 预演，加 `-Execute` 真实清理）。

---

## 阶段 2：关休眠 + 缩虚拟内存（极低风险）

**关休眠**（不用合盖休眠则关掉，立即释放 `hiberfil.sys`，约等于 RAM 大小）：

```powershell
powercfg /h off
```

**缩 pagefile 到 2-4 GB**（仅当 RAM ≥ 16 GB；脚本会自动检测 RAM 并给出建议值）：

```powershell
wmic computersystem set AutomaticManagedPagefile=False
wmic pagefileset where name="C:\\pagefile.sys" set InitialSize=2048,MaximumSize=4096
```

重启后生效。脚本同时备份原设置，方便回滚。

脚本：`scripts/Invoke-Stage2-HiberPagefile.ps1`。

---

## 阶段 3：DISM 清理 WinSxS（极低风险）

```powershell
Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore
Dism.exe /Online /Cleanup-Image /StartComponentCleanup
# 激进版（之后无法卸载已安装的更新）—— 默认不跑，加 -ResetBase 才执行
# Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
```

脚本：`scripts/Invoke-Stage3-DismCleanup.ps1 [-ResetBase]`。

---

## 阶段 4：卸载 UWP 垃圾应用（低风险）

**强烈推荐卸（默认目标）**：

| 包名匹配 | 说明 |
|---|---|
| `*PCManager*`、`*MSPCManager*` | 微软电脑管家（约 800 MB） |
| `*Timeline*` | 时间线（已弃用） |
| `*WebExperience*` | Win11 小组件 |
| `*GetHelp*` | 获取帮助 |
| `*DevHome*` | 开发者主页 |
| `*IntelArcSoftware*` | Intel Arc 软件（核显机型不需要） |
| `*ZuneVideo*` | 电影和电视 |

**询问后再决定**：

| 包名匹配 | 何时保留 |
|---|---|
| `*YourPhone*`、`*CrossDevice*` | 用安卓手机投屏 |
| `*communicationsapps*` | 用 Windows 自带邮件/日历 |
| `*BingNews*`、`*BingWeather*`、`*MicrosoftSolitaireCollection*`、`*Xbox*` | 不用就卸 |

脚本：`scripts/Invoke-Stage4-UwpBloat.ps1`，参数：
- `-AggressiveList`：包含「询问后」列表里的常见冗余包
- `-DryRun`：只列出匹配的包不卸载

assistant 在执行前应展示匹配到的包名给用户确认。

---

## 阶段 5：移动大型 UWP 应用到其他盘（极低风险）

Win10/11 支持把 UWP 应用从 C 盘搬到 D / E 盘而不重装。

**手动操作**：
1. `Win+I → 应用 → 已安装的应用`
2. 找到目标应用 → `⋯ → 移动 → 选目标盘`

**改默认安装位置**（之后 Store 装的新应用自动到目标盘）：
`设置 → 系统 → 存储 → 高级存储设置 → 保存新内容的位置 → 新的应用将保存到 → D 盘`

**脚本辅助**：`scripts/Invoke-Stage5-MoveApps.ps1` 会列出 C 盘上 ≥ 200 MB 的 UWP 应用并打开「已安装的应用」窗口（UWP 应用移动需要 GUI 触发，无 PowerShell API）。

---

## 阶段 6：删除重复驱动（中风险，分批做）

`DriverStore`（`C:\Windows\System32\DriverStore\FileRepository`）经常累积同一驱动的多个版本，旧版可以删。

**流程**：
1. `scripts/Get-DuplicateDrivers.ps1` 生成两个文件到当前目录：
   - `duplicate-drivers.csv` —— 给用户审查
   - `delete-old-drivers.ps1` —— 删除命令（**默认全部注释**）
2. assistant **必须** 提醒用户：
   - **不要尝试删** `ntprint.inf`、`prnms*.inf`（系统自带打印机驱动）—— 脚本会自动从候选列表移除
   - 排序异常时手动复核（脚本按版本号降序保留最新版）
3. **分三批执行**，每批做完重启验证：
   - **第 1 批**：显卡相关（`iigd_ext.inf`、`igdkmd*.inf`、`cui_dch.inf`、`igcc_dch.inf`、`mshdadac.inf`、NVIDIA `nv*.inf`、AMD `ati*.inf`）
   - **第 2 批**：蓝牙（`ibtusb.inf`、`btha*.inf`）
   - **第 3 批**：剩余（网卡、音频、芯片组等）

脚本：
- `scripts/Get-DuplicateDrivers.ps1`
- `scripts/Invoke-Stage6-DriverCleanup.ps1 -Batch {Display|Bluetooth|Rest}`

**出问题怎么办**：设备管理器 → 右键设备 → 更新驱动 → 自动搜索，Windows Update 会重新装回去。

---

## 阶段 7：卸载 OEM 预装软件（中风险）

按 OEM 厂商列举常见冗余，**只提示不自动卸**：

| 厂商 | 常见冗余 | 说明 |
|---|---|---|
| Dell | `Dell SupportAssist`、`Dell SupportAssist OS Recovery Plugin`、`Dell Update`、`Dell Optimizer` | SupportAssist 有历史漏洞 |
| Lenovo | `Lenovo Vantage`、`Lenovo Now`、`Lenovo Welcome` | Vantage 替代品多 |
| HP | `HP Support Assistant`、`HP JumpStart`、`HP Wolf Security` | |
| ASUS | `MyASUS`、`ASUS GiftBox` | |
| Acer | `Acer Care Center`、`Acer Collection` | |
| 通用 | McAfee LiveSafe / WebAdvisor、Norton 试用、ExpressVPN 试用 | 试用期捆绑 |

⚠️ 谨慎卸：`Dell Core Services` 影响功能键/电源；Lenovo `System Interface Foundation` 影响 Fn 键。

脚本：`scripts/Invoke-Stage7-OemBloat.ps1` 列出已装的、匹配厂商关键字的程序，用户勾选后调用 `winget uninstall` 或 MSI 卸载。

---

## 阶段 8：删除 OEM 出厂预装包（中风险，最后做）

OEM 出厂可能在 `C:\Recovery\Customizations\*.ppkg`、`C:\Recovery\OEM\*` 留有预装应用包，单个文件可达 6 GB。用过一次后不再需要。

**先确认日期**：
```powershell
Get-ChildItem "C:\Recovery\" -Recurse -Include *.ppkg -Force |
  Select-Object FullName, @{N='SizeGB';E={[math]::Round($_.Length/1GB,2)}}, LastWriteTime
```

**强制备份后删除**：脚本会强制要求 `-BackupDir` 指向非 C 盘路径，先 `Copy-Item`，校验大小一致后才 `Remove-Item`。

脚本：`scripts/Invoke-Stage8-RemovePpkg.ps1 -BackupDir D:\Backup-OEM-ppkg`。

---

## 补充：AppData 占用审查

很多空间消耗在 `AppData\Local`（Electron 应用缓存、Edge/Chrome 缓存、IDE 缓存）。`scripts/Get-AppDataTopConsumers.ps1` 输出 Top 15：

```powershell
# AppData\Local Top 15
# AppData\Roaming Top 15
```

常见可清理大户：
- `%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache`
- `%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache`
- `%LOCALAPPDATA%\Packages\*\LocalCache`（UWP 缓存）
- `%LOCALAPPDATA%\npm-cache`、`%LOCALAPPDATA%\pip\Cache`、`%LOCALAPPDATA%\Yarn\Cache`
- `%LOCALAPPDATA%\Docker`、`%LOCALAPPDATA%\JetBrains\*\caches`

---

## 应急回滚表

| 故障 | 恢复方法 |
|---|---|
| 驱动删错了 | 设备管理器 → 右键设备 → 更新驱动 → 自动搜索 |
| 关了休眠想恢复 | `powercfg /h on` |
| Pagefile 调小后系统变慢 | 改回「自动管理所有驱动器的分页文件大小」 |
| UWP 误删 | Microsoft Store 搜索重装 |
| WinSxS 清得太狠 | 无法回滚；仅影响「卸载历史更新」，平时无感 |
| 删了 ppkg 后悔 | 从备份目录拷回原位置 |

---

## 推荐执行节奏

- **第 1 天**：阶段 1-5（约 30 分钟，省 15+ GB，全是极低风险）
- **第 2 天**：阶段 6 第 1 批（显卡驱动）→ 重启 → 用一晚验证
- **第 3 天**：阶段 6 第 2 批 + 阶段 7
- **一周后**全部正常：阶段 8

预期：可用空间 **+25 ~ +35 GB**。

---

## Assistant 行为规约

1. **必须**先跑 `Get-DiskReport.ps1`，把 before 数值显示给用户。
2. 阶段 1 之后**必须**再跑一次 `Get-DiskReport.ps1`，给出 reclaimed 差值。
3. 阶段 2、6、7、8 每个**子项**都要单独询问，不要打包确认。
4. 阶段 3 默认**不**使用 `/ResetBase`，仅在用户明确同意后加。
5. 阶段 6 自动从删除清单中剔除 `ntprint.inf`、`prnms*.inf`、当前活跃驱动版本。
6. 阶段 8 没有 `-BackupDir` 参数则**拒绝执行**。
7. 所有 `Remove-Item -Recurse -Force` 前必须校验目标路径前缀属于白名单：`C:\Windows\Temp`、`$env:TEMP`、`$env:LOCALAPPDATA\Temp`、`C:\Windows\SoftwareDistribution\Download`、`C:\Windows\Prefetch`、`C:\Recovery\Customizations`。
8. 数字格式：`'{0:N2} GB' -f ($bytes/1GB)`。
9. 完成后输出一行可复制摘要：`Before X.XX GB → After Y.YY GB（释放 Z.ZZ GB）`。
10. 提醒重启触发项：阶段 2 关休眠/改 pagefile、阶段 3 DISM、阶段 6 删驱动。

## 文件清单

```
SKILL.md
scripts/
  Get-DiskReport.ps1
  Get-AppDataTopConsumers.ps1
  Get-DuplicateDrivers.ps1
  Invoke-Stage1-TempClean.ps1
  Invoke-Stage2-HiberPagefile.ps1
  Invoke-Stage3-DismCleanup.ps1
  Invoke-Stage4-UwpBloat.ps1
  Invoke-Stage5-MoveApps.ps1
  Invoke-Stage6-DriverCleanup.ps1
  Invoke-Stage7-OemBloat.ps1
  Invoke-Stage8-RemovePpkg.ps1
  Clean-All.ps1
  _Common.ps1
```
