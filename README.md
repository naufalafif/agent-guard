# AgentGuard

Native macOS menu bar app that monitors your AI development environment for security threats — scanning both MCP server configs and AI agent skills.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square) ![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square) ![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

<p align="center">
  <img src="screenshot.png?v=2" width="600" alt="AgentGuard" />
</p>

## What it does

AgentGuard sits in your menu bar and periodically scans for security issues using [Cisco AI Defense](https://github.com/cisco-ai-defense) scanners:

| Scanner | What it checks |
|---------|---------------|
| **mcp-scanner** | MCP server configs — Claude Desktop, Cursor, VS Code, Windsurf, Zed |
| **skill-scanner** | AI agent skills — Cursor rules, Claude skills, Codex, Cline, Gemini, and more |

The menu bar icon reflects your security status at a glance:

- **Shield with checkmark** — all clear, no findings
- **Shield with exclamation + count** — active findings detected
- **Half shield** — scan in progress

Click the icon to see findings grouped by scanner, expand details, mute/unmute individual findings, and trigger a rescan.

---

## Installation

### Quick install (Homebrew)

```bash
brew tap naufalafif/tap
brew install --cask agent-guard
open /Applications/AgentGuard.app
```

### Build from source

```bash
git clone https://github.com/naufalafif/agent-guard.git
cd agent-guard
make install    # Builds and copies to /Applications
```

### Prerequisites

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)

That's it. AgentGuard automatically installs all scanner dependencies (`uv`, `mcp-scanner`, `skill-scanner`) on first launch. No manual setup needed.

---

## User Guide

### Menu bar icon

The shield icon updates automatically after each scan:

| Icon | Meaning |
|------|---------|
| Checkmark shield | No active findings |
| Exclamation shield + number | Active findings (number = count) |
| Half shield (animated) | Scan in progress |

### Popover

Click the icon to open the popover:

**MCP Servers** — findings from `mcp-scanner` across your MCP config files. Shows tool count, server count, and config files scanned.

**AI Agent Skills** — findings from `skill-scanner` across your skill directories. Shows total skills scanned.

Each section has:
- **Findings** — click to expand details, then "Mute this finding" with confirmation
- **Safe (N)** — expandable list of servers/skills with no issues
- **Muted (N)** — expandable list of muted findings, click to unmute

### Settings

Open Settings from the gear icon in the popover, or by launching AgentGuard again from Spotlight/Finder.

- **Scan interval** — how often the scanners run (default: 30 minutes)
- **Skill directories** — one per line, overrides the default list
- **Launch at login** — start AgentGuard when you log in

### Muting findings

Muting hides a finding from the active count without deleting it. Useful for known false positives or accepted risks.

1. Click a finding row to expand it
2. Click "Mute this finding"
3. Confirm by clicking "Mute"

Muted findings persist across scans. Unmute anytime from the Muted section.

### Skill directories

By default, AgentGuard scans these directories for AI agent skills:

```
~/.cursor/skills    ~/.cursor/rules     ~/.claude/skills
~/.agents/skills    ~/.codex/skills     ~/.cline/skills
~/.opencode/skills  ~/.config/opencode  ~/.continue/skills
~/.gemini/skills    ~/.codeium/windsurf/skills
~/.kiro/skills      ~/.aider            ~/.gpt-engineer
```

Override from Settings, or in `~/.config/mcp-scan/config`:

```bash
SKILL_DIRS="$HOME/Workspace/projects:$HOME/.agents/skills"
```

---

## How it works

1. **Auto-installs dependencies** on first launch — `uv`, `mcp-scanner`, and `skill-scanner` are installed automatically if missing
2. **Scans in background** — runs both scanners concurrently using `Process` with argument arrays (no shell interpolation)
3. **Parses JSON results** — extracts findings, severity, threat names, safe servers/skills
4. **Updates menu bar** — icon and count reflect the combined threat level
5. **Periodic rescans** — checks on the configured interval, click "Scan Now" for immediate rescan

### Architecture

```
Sources/AgentGuard/
├── main.swift                    # App entry point
├── AgentGuardApp.swift           # NSStatusItem, popover, scan lifecycle
├── Models/
│   ├── Finding.swift             # Finding, SafeItem, Severity
│   └── ScanState.swift           # Observable state, ScannerInfo
├── Services/
│   ├── ScannerService.swift      # Process execution, JSON parsing, ignore list
│   ├── DependencyManager.swift   # Auto-installs uv, mcp-scanner, skill-scanner
│   └── ScreenshotValidator.swift # UI screenshot capture (debug builds)
└── Views/
    ├── PopoverView.swift         # Main popover layout
    ├── SettingsView.swift        # Settings window
    ├── Components.swift          # FindingRowView, MutedFindingRow, ExpandableHeader
    ├── SeverityBadge.swift       # Colored severity label
    ├── PointerCursor.swift       # NSTrackingArea cursor modifier
    └── ColorHex.swift            # Color(hex:) extension
```

### Files on disk

| Path | Purpose |
|------|---------|
| `~/.config/mcp-scan/config` | Scan interval, custom skill directories |
| `~/.cache/mcp-scan/ignore.json` | Muted findings list |
| `~/.cache/mcp-scan/agentguard.log` | Scan log (appended) |

---

## Development

```bash
make build          # Debug build
make run            # Build + launch .app
make release        # Optimized release build
make install        # Build release + copy to /Applications
make uninstall      # Remove from /Applications
make dist           # Package AgentGuard.zip
make lint           # Run SwiftLint
make format         # Auto-format with swift-format
make check          # Build + lint + format check
make clean          # Remove build artifacts
```

### CI/CD

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `ci.yml` | Push/PR to main | Build, SwiftLint, swift-format, secrets scan |
| `release.yml` | Push tag `v*` | Build release, package `.zip`, create GitHub Release |

To create a release:

```bash
git tag v1.2.0
git push origin v1.2.0
```

---

## Uninstall

```bash
# If installed via Homebrew
brew uninstall --cask agent-guard

# If installed via make
make uninstall

# Remove data (optional)
rm -rf ~/.cache/mcp-scan
rm -rf ~/.config/mcp-scan
```

---

## Credits

- [mcp-scanner](https://github.com/cisco-ai-defense/mcp-scanner) and [skill-scanner](https://github.com/cisco-ai-defense/skill-scanner) by Cisco AI Defense

## License

MIT
