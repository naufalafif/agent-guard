# AgentGuard

Native macOS menu bar app that scans your MCP servers and AI agent skills for security threats.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square) ![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square) ![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square) ![CI](https://github.com/naufalafif/agent-guard/actions/workflows/ci.yml/badge.svg) ![Release](https://github.com/naufalafif/agent-guard/actions/workflows/release.yml/badge.svg)

<p align="center">
  <img src="screenshot.png?v=2" width="500" alt="AgentGuard" />
</p>

## Install

```bash
brew tap naufalafif/tap
brew install --cask agent-guard
```

Or build from source:

```bash
git clone https://github.com/naufalafif/agent-guard.git
cd agent-guard
make install
```

Requires macOS 13+. The app auto-installs scanner dependencies on first launch.

## What it scans

| Scanner | What it checks |
|---------|---------------|
| [mcp-scanner](https://github.com/cisco-ai-defense/mcp-scanner) | MCP server configs — Claude Desktop, Cursor, VS Code, Windsurf, Zed |
| [skill-scanner](https://github.com/cisco-ai-defense/skill-scanner) | Agent skill packages — Cursor rules, Claude skills, and other agent instruction files |

Powered by [Cisco AI Defense](https://github.com/cisco-ai-defense). YARA rules + static analysis. Everything runs locally.

## Usage

- **Menu bar icon** — green = all clear, red + count = findings, half shield = scanning
- **Click** the icon to see findings, grouped by MCP servers and AI skills
- **Expand** a finding to see details — threat name, category, rule
- **Mute** false positives with confirmation, unmute anytime
- **Settings** (gear icon) — scan interval, skill directories, launch at login

> **Tip:** AgentGuard scans common skill locations (`~/.cursor/rules`, `~/.claude/skills`, `~/.claude/plugins`, etc.) by default. If you keep skills inside project directories, add your workspace path in Settings.

## Uninstall

```bash
brew uninstall --cask agent-guard
rm -rf ~/.cache/mcp-scan ~/.config/mcp-scan   # optional: remove data
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, architecture, and CI/CD details.

## License

MIT
