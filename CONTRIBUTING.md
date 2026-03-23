# Contributing

## Prerequisites

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)
- SwiftLint (`brew install swiftlint`) — for linting
- swift-format (`brew install swift-format`) — for formatting

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

## Architecture

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

## How it works

1. **Auto-installs dependencies** on first launch — `uv`, `mcp-scanner`, `skill-scanner`
2. **Scans in background** — runs both scanners concurrently using `Process` with argument arrays
3. **Parses JSON results** — extracts findings, severity, threat names, safe servers/skills
4. **Updates menu bar** — icon and count reflect the combined threat level
5. **Periodic rescans** — on the configured interval, or click "Scan Now"

## Files on disk

| Path | Purpose |
|------|---------|
| `~/.config/mcp-scan/config` | Scan interval, custom skill directories |
| `~/.cache/mcp-scan/ignore.json` | Muted findings list |
| `~/.cache/mcp-scan/agentguard.log` | Scan log (appended) |

## CI/CD

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `ci.yml` | Push/PR to main | Build, SwiftLint, swift-format, secrets scan |
| `release.yml` | Push tag `v*` | Build release, package `.zip`, create GitHub Release |

## Creating a release

```bash
git tag v1.x.0
git push origin v1.x.0
```

The release workflow builds the `.app`, packages it as `AgentGuard.zip`, and creates a GitHub Release. Then update the Homebrew tap (`homebrew-tap`) with the new version and SHA.
