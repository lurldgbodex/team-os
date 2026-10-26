# Architecture

## The idea

> The git repository is both the product and the distribution channel.

Engineers clone one repo and run one installer. After that, a `git pull` is the update mechanism for everything: agents, workflows, guardrails and shared knowledge. There is no server, no package registry and no per-engineer configuration to drift.

## Layers

```
┌───────────────────────────────────────────────────────────────┐
│ Engineer's machine                                            │
│                                                               │
│  Claude Code ──loads──▶ plugin "team-os" (from marketplace)   │
│      │                    ├─ agents/    who does the work     │
│      │                    ├─ skills/    repeatable workflows  │
│      │                    ├─ hooks/     automatic behaviour   │
│      │                    └─ knowledge/ what the team knows   │
│      │                                                        │
│      ├─reads─▶ ~/.claude/settings.json   (rules merged in)    │
│      ├─reads─▶ ~/.claude/CLAUDE.md       (behaviour block)    │
│      └─reads─▶ ~/.claude/team-os/personal/  (private notes)   │
│                                                               │
│  Team OS checkout ◀── git pull ◀── shared remote repo         │
│   (this folder IS the marketplace)                            │
└───────────────────────────────────────────────────────────────┘
```

## Components and why each exists

### 1. Marketplace and plugin
`.claude-plugin/marketplace.json` at the repo root declares a marketplace (`teamdata`) with one plugin (`team-os`) whose source is `./plugins/team-os`. Registering the cloned folder as a marketplace lets Claude Code install and update the plugin from local git, with no publishing step.
`plugin.json` is the manifest: name, version, description.
Only `plugin.json` lives inside `.claude-plugin/`. Agents, skills and hooks sit at the plugin root.

### 2. Subagents (`agents/*.md`)
Markdown files with frontmatter (`name`, `description`, `model`, optional `tools`) and a system prompt.
- `librarian` runs on **Haiku**: cheap, read-heavy work.
- `coder` runs on **Sonnet**: writing code.
Pinning a model per agent is a cost and quality control, set once for the whole team.

### 3. Skills (`skills/<name>/SKILL.md`)
Slash-command workflows. `implement-ticket` is a numbered procedure: ticket → plan → approval → code via `coder` → tests → draft PR → self-review. Skills are plain Markdown, so they are reviewed like any other change.

### 4. Hooks (`hooks/hooks.json`)
Hooks run scripts on Claude Code events, so behaviour does not depend on anyone remembering anything.
- **SessionStart** → `session-start.sh` prints `Team OS · <commit>` and warns when the checkout is behind its upstream. Its output joins the session context.
- **PreToolUse** → `guard.sh` receives the pending tool call as JSON on stdin. It returns a `deny` decision with a reason for dangerous commands. It fails *open* if `jq` is missing, so a broken guard never blocks all work.

### 5. Policy (`policy/`)
Two kinds of rule, one tiny file each, so every change is a one-file pull request.
- `rules/*.json`: permission rules (`deny` / `ask`) with a mandatory `why` and `owner`.
- `behaviour/*.md`: always-on instructions.

`bin/apply-policy.sh` merges them into the engineer's own files:
- `permissions.deny` / `permissions.ask` in `~/.claude/settings.json`
- one marked block in `~/.claude/CLAUDE.md`
- a ledger `~/.claude/team-os/managed-rules.json` of exactly what was added

Design properties: **additive** (nothing the engineer had is removed), **idempotent** (re-applying changes nothing), **reversible** (the ledger makes removal exact).
Hooks and permission rules overlap on purpose: permission rules are the simple declarative layer; the guard hook handles patterns permission matching cannot express (piped installers, force flags anywhere in a command).

### 6. Status line (`hooks/statusline.sh`)
Claude Code pipes session JSON to the script on stdin and shows its output. It prints model, context %, optional 5h/7d usage and the version, coloured yellow from 70% and red from 90%. Usage fields are read defensively and only shown if present.

### 7. Knowledge (`knowledge/`)
Shared facts as Markdown. `index.md` says *when to read each file*, so the `librarian` reads the index first and opens only what it needs. Personal notes extend or override the shared bundle.

### 8. Personal folder (`~/.claude/team-os/personal/`)
Private to the machine, its own git repo with a pre-commit hook that runs `gitleaks` when installed. Never part of this repo.

### 9. Installer, updater, uninstaller
- `install.sh`: prerequisites → save checkout path → register marketplace → install plugin → `post-merge` hook → personal folder → apply policy → status line.
- `post-merge` hook → `bin/refresh.sh`: so `git pull` refreshes plugin and rules.
- `uninstall.sh`: reverses every step, keeps personal notes, restores a previous status line.

## Data flow: an update

```
maintainer merges PR ─▶ shared remote
                              │
engineer: git pull ───────────┘
      │
      ▼
post-merge hook ─▶ bin/refresh.sh
      ├─ claude plugin marketplace update teamdata
      ├─ claude plugin update team-os@teamdata
      └─ bin/apply-policy.sh  (re-merge rules, idempotent)
      │
      ▼
next Claude Code session loads the new version
```

The version is the git commit; `session-start.sh` shows it.

## Data flow: a guarded action

```
Claude decides: run `git push --force`
      │
      ▼
PreToolUse hook ─▶ guard.sh reads JSON on stdin
      │               matches rule ─▶ prints deny + reason
      ▼
Claude Code blocks the call and shows the reason to Claude and the engineer
```

## Decisions and trade-offs

| Decision | Why | Trade-off |
|---|---|---|
| Distribute via git, no server | Zero infrastructure, review via PRs, versions are commits | Engineers must keep the clone and pull |
| Rules merged into user settings | Applies to every project, not only this repo | Must be additive and reversible, hence the ledger |
| One file per rule | Small reviewable PRs, clear ownership | More files |
| Hooks fail open | A broken guard must not stop all work | Guard is a safety net, not a security boundary |
| `jq` for JSON | Ubiquitous, safe atomic edits | One more prerequisite |
| Bash scripts with bats tests | Runs anywhere Claude Code runs, easy to read | Windows needs Git Bash or WSL |
| Agents pin models | Predictable cost and quality | Must be revisited as models change |

## Limits and honest caveats

- The guard is **defence in depth, not a sandbox**. A determined user or a cleverly written command can get around pattern matching. Real protection for production still belongs in IAM, CI and network controls.
- A hook cannot switch the session's model. A "model guide" can only advise or ask the engineer to run `/model`.
- Plugin and CLI subcommands (`claude plugin ...`) and hook JSON formats evolve. The installer reports failures and prints the manual `/plugin` command as a fallback. Verify against the current docs when upgrading Claude Code.
- Usage percentages (5h/7d) depend on fields Claude Code provides to the status line. They are shown only when present.

## Extending it

| To add | Do this |
|---|---|
| An agent | `plugins/team-os/agents/<name>.md` with frontmatter and a prompt |
| A workflow | `plugins/team-os/skills/<name>/SKILL.md` |
| A guardrail | One file in `policy/rules/` (and a test in `tests/guard.bats` if it is a hook rule) |
| Knowledge | A file in `knowledge/` plus a row in `index.md` |
| Scheduled routines | A `routines/` folder of prompts each engineer links in (roadmap) |

Run `bin/test.sh` before opening a PR.
