---
title: You probably haven't audited your MCP servers or AI agent skills. This tool does it for you.
published: false
cover_image: https://raw.githubusercontent.com/naufalafif/agent-guard/main/cover.png
tags: security, ai, macos, opensource
---

New MCP servers and AI agent tools ship every week. Cursor rules, Claude skills, agent instructions — the ecosystem is moving faster than anyone can manually review.

Even if you check things before installing, updates can introduce new behavior. And with tools being forked, modified, and reshared — you want something watching continuously.

That's why I built **AgentGuard** — a macOS menu bar app that runs security scanners in the background and flags anything suspicious.

## The risk

MCP servers register tools that your AI assistant calls. Those tools can read files, run commands, make HTTP requests. A malicious or compromised tool can:

- Exfiltrate your SSH keys or credentials to an external endpoint
- Inject prompts that override your instructions
- Chain tool calls to escalate access

Same with agent skills and rules (`.cursorrules`, Claude skills, agent instructions). They're mostly markdown files — but they control what the AI does on your machine.

## The scanners

Cisco AI Defense maintains two open-source security scanners:

| Scanner | What it scans |
|---------|--------------|
| [mcp-scanner](https://github.com/cisco-ai-defense/mcp-scanner) | MCP server configs — Claude Desktop, Cursor, VS Code, Windsurf, Zed |
| [skill-scanner](https://github.com/cisco-ai-defense/skill-scanner) | Agent skill packages — Cursor rules, Claude skills, and other agent instruction files |

YARA rules + static analysis. Everything runs locally, nothing leaves your machine.

They work great — but they're CLI tools. You have to remember to run them manually after every install or update.

## AgentGuard

AgentGuard puts both scanners behind a menu bar icon. It scans on a schedule, shows findings in a popover, and lets you act on them.

![AgentGuard popover showing findings](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/pv2k1ainq7oyalpv74eq.png)

Click a finding to see full details — what was detected, which rule flagged it, and the option to mute it:

![Finding expanded with details](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/xiqo7e3ljv7a9iio8zdz.png)

**What you get:**

- Shield icon in menu bar — green when clear, red + count when there are findings
- MCP Servers and AI Agent Skills as separate sections
- Click to expand finding details — threat name, category, rule ID
- Mute with confirmation — dismiss known false positives, unmute anytime
- Settings — scan interval, custom skill directories, launch at login

**Install:**

```bash
brew tap naufalafif/tap
brew install --cask agent-guard
```

The app handles everything — installs the scanners, scans your configs, runs in the background. No manual setup.

**What it scans:**

MCP configs are picked up automatically — `claude_desktop_config.json`, `.cursor/mcp.json`, VS Code `settings.json`, Windsurf, Zed.

Skill directories default to common locations — `~/.cursor/skills`, `~/.cursor/rules`, `~/.claude/skills`, `~/.agents/skills`, and more. Add your own from Settings.

## Open source

AgentGuard is a native Swift app — open source under MIT.

GitHub: **[github.com/naufalafif/agent-guard](https://github.com/naufalafif/agent-guard)**

If you use MCP servers or AI coding tools, give it a scan. You might find something you didn't expect.
