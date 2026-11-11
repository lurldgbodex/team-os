# Team OS

One install gives every engineer the same Claude Code toolkit: shared subagents, an end-to-end ticket workflow, guardrails that block dangerous actions, a status line, and a curated knowledge bundle. It ships as a Claude Code **plugin** from this git repo, so every merge reaches every machine on the next `git pull`.

> Proof of concept. The structure mirrors a production-grade team toolkit; the content (rules, knowledge, agents) is a starter you replace with your team's own.

## What you get

| Piece | Name | What it does |
|---|---|---|
| Subagent | `team-os:librarian` | Reads the shared knowledge and your personal notes before anyone digs through code (Haiku) |
| Subagent | `team-os:coder` | Writes scoped code following team standards (Sonnet) |
| Subagent | `team-os:reviewer` | Read-only code reviewer: correctness, security, tests, scope (Sonnet) |
| Skill | `/team-os:create-ticket <description>` | Rough idea → GitHub issue with acceptance criteria, created after you approve |
| Skill | `/team-os:implement-ticket 42` | Issue → plan → code → tests → draft PR that closes it → self-review |
| Skill | `/team-os:review-pr 57` | PR + linked issue → findings by severity → optional posted review |
| Skill | `/team-os:setup` | Post-install check and one-minute tour. Safe to re-run |
| Skill | `/team-os:stats [weeks]` | Guard blocks by rule and week from your local audit log, plus your PRs that close an issue |
| Hook | session start | Prints `Team OS · <version>` and warns when your checkout is behind |
| Hook | guard | Blocks force pushes, piped installers, `.env` reads, local deploys, prod DB access. Each block is logged locally to `~/.claude/team-os/audit.jsonl` (no command text) |
| Status line | | Model · context % · optional 5h/7d usage · version. Yellow at 70%, red at 90% |
| Policy | `plugins/team-os/policy/` | One small file per rule, merged into your own Claude settings, reversible |
| Knowledge | `plugins/team-os/knowledge/` | Shared facts, `index.md` first |
| Personal folder | `~/.claude/team-os/personal/` | Private notes, own git repo, secret-scan hook, never pushed here |

## Requirements

- Claude Code (current version) and a Claude seat (log in with `claude`)
- `git`, the GitHub CLI `gh` (logged in), and `jq` (the installer installs `jq` when it can)
- `gitleaks` is optional: it lets the personal folder block commits that contain secrets
- Windows: use Git Bash or WSL for now (a PowerShell installer is on the roadmap)
- **Keep the cloned folder.** It is the plugin marketplace on your machine. `git pull` there is how new versions arrive

## Install

```bash
git clone <this-repo-url> team-os
cd team-os
./install.sh
```

Then exit Claude Code, start it again, and run `/team-os:setup`.

Manual fallback, if the installer cannot call the `claude` CLI: inside Claude Code run `/plugin marketplace add <path-to-this-folder>` then `/plugin install team-os@teamdata`.

Non-interactive: `./install.sh --yes`. Keep your own status line: `./install.sh --status-line keep`.

## After installing

- Ask anything about a project. The `librarian` reads the shared knowledge first.
- `/team-os:create-ticket add FX rate caching` drafts a GitHub issue and creates it once you approve.
- `/team-os:implement-ticket 42` takes issue #42 to a draft pull request that closes it.
- `/team-os:review-pr 57` reviews pull request #57 and can post the findings as a review.
- `/team-os:stats` shows how often the guard blocked something and how many of your PRs closed an issue.
- Try asking Claude to read `.env`: the guard blocks it and says why.
- Tickets are GitHub Issues. The GitHub connector is optional (connect it at claude.ai/settings/connectors, then run `/mcp`); without it the skills use the `gh` CLI.

## Updating

```bash
./update.sh        # macOS / Linux
```

A plain `git pull` in this folder does the same: the installer adds a `post-merge` hook that refreshes the plugin and rules, so a new rule reaches you without re-running the installer. New Claude Code sessions pick up the new version. The version is the git commit.

## Uninstall

```bash
./uninstall.sh
```

Takes out the plugin, marketplace, rules, hook and status line (restoring yours if you had one). Your personal notes are kept.

## Contributing

- Add or change a rule: one small file under `plugins/team-os/policy/` (JSON with `why` and `owner`, or one Markdown file per behaviour rule).
- Add knowledge: a file in `plugins/team-os/knowledge/` plus one row in `index.md`.
- Before opening a PR: `bin/test.sh` (hygiene check + bats tests). CI (`.github/workflows/ci.yml`) runs the same checks plus shellcheck on every pull request and push to main.
- Architecture and design decisions: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- Walking the team through it: [docs/DEMO.md](docs/DEMO.md).

## Repo layout

```
install.sh / uninstall.sh / update.sh   thin entry points
.claude-plugin/marketplace.json         the "teamdata" marketplace: one plugin, team-os
plugins/team-os/
  .claude-plugin/plugin.json            plugin manifest
  agents/                               librarian, coder, reviewer
  skills/                               create-ticket, implement-ticket, review-pr, setup, stats
  hooks/                                hooks.json, session-start.sh, guard.sh, statusline.sh
  knowledge/                            shared knowledge bundle (index.md first)
  policy/                               rules/*.json and behaviour/*.md, one file per rule
bin/                                    lib.sh, apply-policy.sh, refresh.sh, hygiene.sh, test.sh
tests/                                  bats tests for every script
docs/                                   ARCHITECTURE.md, DEMO.md
```
