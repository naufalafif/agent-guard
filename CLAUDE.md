# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

AgentGuard is a native macOS menu bar app that scans MCP server configs and AI agent skills for security threats. It wraps Cisco's `mcp-scanner` and `skill-scanner` CLI tools, running them in the background and presenting findings in a native popover UI.

Project goals:

- **Zero-config**: Install via `brew install --cask agent-guard`, app auto-installs scanner dependencies on first launch
- **Always-on**: Sits in menu bar, scans periodically, updates icon with threat count
- **Native UX**: SwiftUI popover + AppKit NSStatusItem, no Electron/web views
- **Security-first**: This is a security tool — no shell string interpolation, hardened file permissions, argument arrays for all process execution

## Architecture

```
Sources/AgentGuard/
├── main.swift                    # Entry point (MainActor.assumeIsolated)
├── AgentGuardApp.swift           # AppDelegate: NSStatusItem, popover, scan lifecycle, settings window
├── Models/
│   ├── Finding.swift             # Finding, SafeItem, Severity types
│   └── ScanState.swift           # @Published observable state, ScannerInfo
├── Services/
│   ├── ScannerService.swift      # Process execution, JSON parsing, config, ignore list
│   ├── DependencyManager.swift   # Auto-installs uv, mcp-scanner, skill-scanner
│   └── ScreenshotValidator.swift # UI screenshot capture (DEBUG builds only)
└── Views/
    ├── PopoverView.swift         # Main popover layout with MCP + Skills sections
    ├── SettingsView.swift        # Settings window (interval, skill dirs, launch at login)
    ├── Components.swift          # FindingRowView, MutedFindingRow, ExpandableHeader
    ├── SeverityBadge.swift       # Colored severity label component
    ├── PointerCursor.swift       # NSTrackingArea-based cursor modifier
    └── ColorHex.swift            # Color(hex:) extension
```

## Important Security Rules

This is a security scanning tool. Follow these rules strictly:

- **NEVER use shell string interpolation** for process execution. Always use `Process` with `arguments` array via `runProcess()`. The legacy `shell()` method is dead code — do not call it, and ideally delete it.
- **NEVER pass user/config-derived values through bash**. Skill directory paths from config must go through `Process.arguments`, never interpolated into a shell command string.
- **Use `resolveExecutable()`** to find scanner binaries — checks known paths (`~/.local/bin/`, `/opt/homebrew/bin/`, etc.) then falls back to `/usr/bin/which` with argument arrays.
- **File permissions**: Cache directory must be `0o700`, ignore list `0o600`. Use `atomicWriteIgnoreList()` for writes.
- **Temp files**: Use UUID names under the cache dir. Always clean up in all code paths.

## Dev Commands

```bash
make build          # Debug build
make run            # Build + launch .app bundle
make release        # Optimized release build
make install        # Build release + copy to /Applications
make uninstall      # Remove from /Applications
make lint           # SwiftLint (brew install swiftlint)
make format         # swift-format (brew install swift-format)
make check          # Build + lint + format check
make clean          # Remove build artifacts
```

Do NOT run `swift run` — the app needs a `.app` bundle with `Info.plist` and `AppIcon.icns` to show the menu bar icon. Always use `make run`.

## First-Time Setup

After cloning, install git hooks:

```bash
./scripts/setup-hooks.sh
```

This installs a `pre-push` hook that runs `make check` (build + lint + format) before every push. Both humans and AI should always have this active.

## PR Conventions

PR titles must follow conventional commits:

```
feat: add new scanner support
fix: resolve pipe deadlock in .app bundles
chore: update CI workflow
docs: improve README installation section
refactor: extract scan logic into service
```

CI enforces this — PRs with non-conforming titles will fail.

## Git Workflow

Uses gitflow:

```
feat/my-feature  →  staging  →  main  →  tag  →  release
```

- **`staging`** — default branch, all PRs target here
- **`main`** — production-ready, releases come from here
- **Feature/fix branches** — branch from `staging`, PR back to `staging`
- **Release** — merge `staging` → `main`, then tag on `main`

```bash
# New feature
git checkout staging
git checkout -b feat/my-feature
# ... make changes ...
git push -u origin feat/my-feature
gh pr create --base staging

# Release (after PR merged to staging, then staging merged to main)
./scripts/release.sh 1.4.0
```

## Releasing

Two options:

**Option 1: Local script (does everything)**

```bash
./scripts/release.sh 1.4.0
```

Automates: version bump in Info.plist → commit → tag → push → wait for CI → update homebrew-tap.

**Option 2: Just tag on main (CI handles the rest)**

```bash
# On main branch, after merging staging:
git tag v1.4.0
git push origin v1.4.0
```

The release workflow builds the `.app`, creates a GitHub Release, and **automatically updates the Homebrew tap** (`naufalafif/homebrew-tap`) with the new version and SHA via `TAP_TOKEN` secret.

**Important:** Never retag the same version — always bump the version number so `brew upgrade` works.

## Key Technical Decisions

### Menu bar icon: NSHostingView subview (not NSImage)

`NSImage(systemSymbolName:)` returns `nil` for many SF Symbols when run from an SPM-built `.app` bundle. We use a `ClickThroughHostingView` (NSHostingView subclass with `hitTest` returning `nil`) embedded as a subview of the status bar button. This renders SF Symbols reliably via SwiftUI while passing clicks through to the parent button.

### Process execution: temp file stdout (not Pipe)

`NSPipe.readDataToEndOfFile()` deadlocks when run from a `.app` bundle context. We redirect process stdout to a temp file, poll `process.isRunning` via `Task.detached`, then read the file after exit. Always call `synchronizeFile()` + `close()` before reading — without this, large outputs (like mcp-scanner's 63KB JSON) get truncated.

### Settings window: Ice-style activation

Opening a settings window from an `LSUIElement` (menu bar-only) app requires:
1. `NSApp.setActivationPolicy(.regular)` to show in Dock
2. First activation needs the Dock hack: activate Dock process first, then 200ms delay, then activate self
3. Center using `screen.visibleFrame` (not `window.center()` which positions upper-third)
4. `setFrameAutosaveName` to remember user's window position
5. Revert to `.accessory` policy when settings window closes

### Swift concurrency

`AppDelegate` is `@MainActor`. The `main.swift` entry point uses `MainActor.assumeIsolated {}` because top-level code runs on the main thread but Swift 6 doesn't know that. Timer-based scheduling was replaced with `Task`-based async loops to avoid GCD dispatch issues in `.app` bundles.

## Code Style

- Target macOS 13+. Do NOT use APIs that require macOS 14+ (e.g., `symbolEffect`, `onChange` with two params).
- Check SF Symbol availability before using — some symbols don't exist on macOS 13. Test with: `swift -e 'import AppKit; print(NSImage(systemSymbolName: "your.symbol", accessibilityDescription: nil) != nil)'`
- Use `.buttonStyle(.plain)` + `.pointerCursor()` for clickable elements in the popover.
- SwiftLint is strict (`--strict`). Fix all warnings before pushing. Key rules: no force unwrapping, line length ≤ 140, use `for-where` over `for+if`.
- Keep views composable. Popover sections (MCP, Skills) share patterns — if adding a third scanner, follow the same structure.

## Tests and Validation

- `make check` runs build + lint + format check.
- DEBUG builds auto-capture popover screenshots to `~/.cache/mcp-scan/screenshots/` on every popover open.
- Scan results are logged to `~/.cache/mcp-scan/agentguard.log` (appended, not overwritten).
- CI runs on every push: build (debug + release), SwiftLint, swift-format, secrets scan.

## Files on Disk

| Path | Purpose | Permissions |
|------|---------|-------------|
| `~/.config/mcp-scan/config` | Scan interval, SKILL_DIRS | User default |
| `~/.cache/mcp-scan/ignore.json` | Muted findings | 0o600 |
| `~/.cache/mcp-scan/agentguard.log` | Scan log | User default |
| `~/.cache/mcp-scan/screenshots/` | Debug screenshots | 0o700 |
| `~/.cache/mcp-scan/proc-*.tmp` | Temp process output | Cleaned up after read |

## Common Pitfalls

- **Pipe deadlock**: Never use `Pipe.readDataToEndOfFile()` for subprocess stdout in `.app` bundles. Use temp files.
- **SF Symbol availability**: `shield.checkmark.fill` doesn't exist on macOS 13. Use `checkmark.shield.fill` instead.
- **FileHandle flush**: Always call `synchronizeFile()` before `close()` when reading a file that was written by a subprocess via FileHandle.
- **Concurrent scans**: `performScan()` has a `guard !state.isScanning` check. Don't remove it.
- **Config `$HOME` expansion**: The config file uses literal `$HOME` which must be replaced with the actual path at parse time.
