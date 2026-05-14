# win-c-cleaner

> 中文版 README：[README.md](./README.md)

A universal Windows 10 / 11 **C: drive cleanup Skill** for Claude. Follows an 8-stage "low-risk → high-yield" playbook that can typically reclaim **25–35 GB** of system-drive space.

The repository itself is a **Claude Skill**: one `SKILL.md` plus a set of PowerShell helpers. Any client that speaks the Anthropic Skills protocol (Claude Code, Claude Desktop, Claude Agent SDK, etc.) can load it and trigger it automatically.

---

## Feature overview

| Stage | Action | Time | Yield | Risk |
|-------|--------|------|-------|------|
| 1 | Temp files / caches / Recycle Bin / crash dumps | 5 min | 3–8 GB | very low |
| 2 | Disable hibernation (`hiberfil.sys`) + shrink pagefile | 2 min | 8–10 GB | very low |
| 3 | DISM WinSxS component store cleanup | 10–20 min | 2–3 GB | very low |
| 4 | Uninstall UWP bloat (PCManager, Widgets, Bing News, …) | 5 min | 1–1.5 GB | low |
| 5 | Move large UWP apps to a non-system drive | 5 min | 1+ GB | very low |
| 6 | Delete duplicate old drivers from `DriverStore` (batched) | 20–30 min | 3–5 GB | medium |
| 7 | Uninstall OEM bloatware (Dell / Lenovo / HP / ASUS / Acer / trial AV) | 5 min | 0.5–1 GB | medium |
| 8 | Delete OEM provisioning packages `C:\Recovery\Customizations\*.ppkg` | 2 min | 1–6 GB | medium (backup required) |

**Safety design**
- Requires Administrator PowerShell + Win10/11 self-check
- Every destructive `Remove-Item` is guarded by a path whitelist (`Test-SafePath`); anything outside is refused
- Stage 1 is dry-run by default; needs `-Execute` for real deletion
- Stage 3 `/ResetBase`, Stage 6 driver delete, and Stage 8 ppkg delete all require explicit flags + second confirmation
- Stage 6 automatically removes `ntprint.inf` / `prnms*.inf` from the candidate list (built-in print drivers; `pnputil` can't remove them)
- Stage 8 forces `-BackupDir` to point at a non-system drive, copies and size-verifies before removing the original

---

## Repository layout

```
.
├── LICENSE
├── README.md                              # Chinese
├── README.en.md                           # this file
└── skills/
    └── win-c-cleaner/
        ├── SKILL.md                       # Skill triggers + behavior rules + 8-stage manual
        └── scripts/
            ├── _Common.ps1                # shared: elevation / OS check / whitelist delete / reporting
            ├── Get-DiskReport.ps1         # before/after disk report
            ├── Get-AppDataTopConsumers.ps1# AppData Local/Roaming Top 15
            ├── Get-DuplicateDrivers.ps1   # duplicate-driver scan → CSV + commented script
            ├── Invoke-Stage1-TempClean.ps1
            ├── Invoke-Stage2-HiberPagefile.ps1
            ├── Invoke-Stage3-DismCleanup.ps1
            ├── Invoke-Stage4-UwpBloat.ps1
            ├── Invoke-Stage5-MoveApps.ps1
            ├── Invoke-Stage6-DriverCleanup.ps1
            ├── Invoke-Stage7-OemBloat.ps1
            ├── Invoke-Stage8-RemovePpkg.ps1
            └── Clean-All.ps1              # orchestrates stages 1–5, prompts for 6–8
```

---

## Install

### Option A — as a Claude Skill (recommended)

#### Claude Code (CLI / Desktop / VS Code extension)

Copy `skills/win-c-cleaner/` into your local skills directory:

```powershell
# Windows
git clone https://github.com/Gutiz/win-c-cleaner.git
$dst = "$env:USERPROFILE\.claude\skills\win-c-cleaner"
New-Item -ItemType Directory -Path $dst -Force | Out-Null
Copy-Item -Path .\win-c-cleaner\skills\win-c-cleaner\* -Destination $dst -Recurse -Force
```

```bash
# macOS / Linux (manage the skill cross-machine; scripts still run on Windows)
git clone https://github.com/Gutiz/win-c-cleaner.git
mkdir -p ~/.claude/skills
cp -r win-c-cleaner/skills/win-c-cleaner ~/.claude/skills/
```

For project scope, place it at `<project>/.claude/skills/win-c-cleaner/` instead.

After install, just tell Claude **"clean up the C drive"** / **"C盘清理"** and the skill triggers automatically.

#### Claude Desktop

`Settings → Skills → Add Skill → pick the skills/win-c-cleaner folder`, enable it, then use in any conversation.

#### Claude Agent SDK (Python / TypeScript)

```python
from claude_agent_sdk import ClaudeAgentOptions, query

options = ClaudeAgentOptions(
    skills_dirs=["./skills"],            # point at the repo's skills/
    allowed_tools=["Bash", "Read", "Write", "Edit"],
)
async for msg in query(prompt="clean up Windows C drive", options=options):
    print(msg)
```

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

for await (const msg of query({
  prompt: "clean up Windows C drive",
  options: {
    skillsDirs: ["./skills"],
    allowedTools: ["Bash", "Read", "Write", "Edit"],
  },
})) {
  console.log(msg);
}
```

### Option B — run the scripts directly (no agent)

```powershell
# 1. Clone
git clone https://github.com/Gutiz/win-c-cleaner.git
cd win-c-cleaner\skills\win-c-cleaner\scripts

# 2. Open an Administrator PowerShell, allow local scripts
Set-ExecutionPolicy -Scope Process Bypass

# 3. Report + orchestrator (interactive, stages 1–5)
.\Get-DiskReport.ps1
.\Clean-All.ps1
```

---

## Usage examples

### Trigger via Claude

> **You**: My C drive only has 10 GB left, please clean it up.
>
> **Claude**: (Loads the `win-c-cleaner` skill, runs `Get-DiskReport.ps1` for a baseline, then walks you through the stages with confirmations.)

### Run a single stage

```powershell
# Stage 1 - dry-run first
.\Invoke-Stage1-TempClean.ps1            # preview
.\Invoke-Stage1-TempClean.ps1 -Execute   # real clean

# Stage 2 - turn off hibernation (frees hiberfil.sys)
.\Invoke-Stage2-HiberPagefile.ps1 -DisableHibernation

# Stage 3 - DISM WinSxS cleanup (omit -ResetBase for safety)
.\Invoke-Stage3-DismCleanup.ps1

# Stage 4 - UWP bloat
.\Invoke-Stage4-UwpBloat.ps1 -DryRun         # see matches first
.\Invoke-Stage4-UwpBloat.ps1 -AggressiveList # includes Xbox/Bing/etc.

# Stage 5 - list large UWP apps, open Settings page to move them
.\Invoke-Stage5-MoveApps.ps1 -TargetDrive D:

# Stage 6 - duplicate drivers (batched, reboot to verify each batch)
.\Get-DuplicateDrivers.ps1
.\Invoke-Stage6-DriverCleanup.ps1 -ScriptPath .\delete-old-drivers.ps1 -Batch Display
.\Invoke-Stage6-DriverCleanup.ps1 -ScriptPath .\delete-old-drivers.ps1 -Batch Display -Execute

# Stage 7 - OEM bloatware
.\Invoke-Stage7-OemBloat.ps1
.\Invoke-Stage7-OemBloat.ps1 -IncludeRiskyFunctionKeys

# Stage 8 - delete OEM ppkg (backup directory is mandatory)
.\Invoke-Stage8-RemovePpkg.ps1 -BackupDir D:\Backup-OEM-ppkg
```

---

## Suggested pacing

- **Day 1**: Stages 1–5 (~30 min, all very low risk, frees 15+ GB)
- **Day 2**: Stage 6 batch 1 (display drivers) → reboot → verify overnight
- **Day 3**: Stage 6 batch 2 (Bluetooth) + Stage 7
- **One week later**, once everything is stable: Stage 8 (delete ppkg)

---

## Supported agent tools / clients

The skill follows the official Anthropic Skills spec (`SKILL.md` + YAML frontmatter) and works with:

| Client | Load path | Notes |
|--------|-----------|-------|
| **Claude Code CLI** | `~/.claude/skills/` or `<project>/.claude/skills/` | user-scope or project-scope |
| **Claude Code (Web)** | repo `skills/` directory, auto-discovered | combine with a SessionStart hook |
| **Claude Desktop** | Settings → Skills → Add Skill | desktop app |
| **Claude VS Code extension** | same as Claude Code CLI | |
| **Claude Agent SDK (Python)** | `ClaudeAgentOptions(skills_dirs=[...])` | `pip install claude-agent-sdk` |
| **Claude Agent SDK (TypeScript)** | `query({ options: { skillsDirs: [...] } })` | `npm i @anthropic-ai/claude-agent-sdk` |
| **Anthropic API (Skills beta)** | inject via the `skills` parameter | requires Skills access |

The scripts only call standard tools — `Bash`, `Read`, `Write`, `Edit` — and require no external MCP servers.

### Runtime requirements

- **OS**: Windows 10 (10.0.19041+) or Windows 11
- **Shell**: PowerShell 5.1 (built-in) or PowerShell 7+
- **Privileges**: Administrator PowerShell required
- **Optional**: `winget` (Stage 7 prefers it; falls back to MSI/InstallShield silent uninstall)
- A second drive (D: / E: / external) is helpful for Stages 5 and 8 (move target + backup target)

---

## Trigger keywords (CN / EN)

The skill matches the `SKILL.md` frontmatter against these phrases:

- **English**: free up C drive, clean C drive, Windows disk cleanup, WinSxS bloat, Windows.old, hiberfil.sys, pagefile
- **中文**: C 盘清理、清理 C 盘、系统盘满了、系统盘没空间、Windows 磁盘清理、删除休眠文件、缩虚拟内存、WinSxS 清理、Windows.old

It will not fire on macOS or Linux sessions.

---

## Emergency rollback

| Mistake | How to recover |
|---------|---------------|
| Deleted the wrong driver | Device Manager → right-click device → Update driver → search automatically |
| Disabled hibernation, want it back | `powercfg /h on` |
| Pagefile too small, system slow | Re-enable "Automatically manage paging file size for all drives" |
| Removed a UWP app you needed | Reinstall from Microsoft Store |
| Over-cleaned WinSxS | Not reversible; only affects "uninstall existing updates", no day-to-day impact |
| Regret deleting a ppkg | Copy it back from `-BackupDir` into `C:\Recovery\Customizations\` |

---

## Branches

| Branch | Purpose |
|--------|---------|
| `main` | Mainline development |
| `release` | Daily release branch — protected, deployment artifacts cut from here |
| `claude/*` | Claude-generated feature branches |

Pull requests should target `main`. Release rotations cherry-pick or fast-forward from `main` into `release`.

---

## Contributing

Issues and PRs welcome:
- Add more OEM vendor patterns to Stage 7
- Add more UWP package patterns to Stage 4
- Expand `SKILL.md` trigger phrases for additional languages

---

## License

[MIT](./LICENSE)
