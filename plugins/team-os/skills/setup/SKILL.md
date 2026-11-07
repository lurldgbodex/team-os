---
name: setup
description: Post-install check for Team OS. Verifies prerequisites, connectors and rules, then gives a one-minute tour. Safe to re-run.
---

# Team OS setup check

Run these checks and report a short pass/fail list. Fix nothing without asking.

1. **Version**: run `git -C "${CLAUDE_PLUGIN_ROOT}/../.." rev-parse --short HEAD` and report it.
2. **Tools**: check `git`, `gh` (and `gh auth status`), and `jq` are installed.
3. **Connectors**: run `claude mcp list` and report whether GitHub is connected. If it is missing, tell the engineer to open claude.ai/settings/connectors, connect it, then run `/mcp`. The connector is optional: without it the skills fall back to the `gh` CLI. Do not report Atlassian (Jira) as a problem; the team tracks work in GitHub Issues.
4. **Rules**: read `~/.claude/settings.json` and confirm the Team OS deny/ask rules are present (`jq '.permissions.deny' ~/.claude/settings.json`).
5. **Personal folder**: confirm `~/.claude/team-os/personal/` exists and is a git repo.

Then give the one-minute tour:

- Ask any question about our projects. The `librarian` reads the shared knowledge first.
- `/team-os:create-ticket <description>` drafts a GitHub issue and creates it once you approve.
- `/team-os:implement-ticket 42` takes issue #42 to a draft PR that closes it.
- `/team-os:review-pr 57` reviews pull request #57 and can post the findings as a review.
- Dangerous actions (reading `.env`, force pushes, piped installers) are blocked with a reason.
- The status line shows model, context use and Team OS version.
- To update, run `git pull` in the Team OS folder. Rules and the plugin refresh automatically.
