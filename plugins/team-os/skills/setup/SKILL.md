---
name: setup
description: Post-install check for Team OS. Verifies prerequisites, connectors and rules, then gives a one-minute tour. Safe to re-run.
---

# Team OS setup check

Run these checks and report a short pass/fail list. Fix nothing without asking.

1. **Version**: run `git -C "${CLAUDE_PLUGIN_ROOT}/../.." rev-parse --short HEAD` and report it.
2. **Tools**: check `git`, `gh` (and `gh auth status`), and `jq` are installed.
3. **Connectors**: run `claude mcp list` and report whether Atlassian (Jira) and GitHub are connected. If one is missing, tell the engineer to open claude.ai/settings/connectors, connect it, then run `/mcp`.
4. **Rules**: read `~/.claude/settings.json` and confirm the Team OS deny/ask rules are present (`jq '.permissions.deny' ~/.claude/settings.json`).
5. **Personal folder**: confirm `~/.claude/team-os/personal/` exists and is a git repo.

Then give the one-minute tour:

- Ask any question about our projects. The `librarian` reads the shared knowledge first.
- `/team-os:implement-ticket PROJ-123` takes a ticket to a draft PR.
- Dangerous actions (reading `.env`, force pushes, piped installers) are blocked with a reason.
- The status line shows model, context use and Team OS version.
- To update, run `git pull` in the Team OS folder. Rules and the plugin refresh automatically.
