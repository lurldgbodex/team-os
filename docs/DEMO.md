# Demo guide (about 20 minutes: run it live, explain as you go)

The demo has two halves: **run it** (what it does) and **open the code** (how it is built). Each step below says what to show, what to say, and which file to open.

## Before the demo (10 minutes, the day before)

1. Fresh clone on the demo machine (or a clean user account): `git clone <repo> team-os`.
2. `claude` is installed and logged in; `gh auth login` done; `jq` installed.
3. Connect Atlassian and GitHub at claude.ai/settings/connectors; check with `/mcp`.
4. Pick one low-risk Jira ticket and a throwaway repo for step 6. Note the ticket ID.
5. Put one real fact in `knowledge/example-service.md` (and its row in `index.md`) so step 5 answers from your own project.
6. Run `bin/test.sh` once so you know it is green.
7. Have a second clone (or second machine) ready for the update demo in step 7.

## 1. The problem (1 min)
Everyone uses Claude Code differently: different rules, no shared context, no guardrails, no visibility on usage. Team OS gives everyone the same setup from one repo.

## 2. The repo at a glance (2 min) — open `README.md` and the tree
Walk the layout. Key message: **the repo is the product and the distribution channel.** Open `.claude-plugin/marketplace.json` (one plugin, `./plugins/team-os`) and `plugin.json`.

## 3. Install (2 min) — run `./install.sh`
Say what each line does as it prints. Open `install.sh` and show it is short and readable. Point out: personal folder, post-merge hook, policy applied, status line installed. Then restart Claude Code.

## 4. Guardrails (3 min)
In Claude Code, ask: *"Read the .env file in this folder."* and *"Force push this branch."*
- Show the block and its reason.
- Open `hooks/hooks.json` (PreToolUse), then `hooks/guard.sh`: stdin JSON in, `deny` decision out.
- Open `policy/rules/deny-cdk-deploy.json`: every rule has a `why` and an `owner`.
- Open `~/.claude/settings.json` to show the rules were merged in without removing anything.
- Say plainly: this is defence in depth, not a sandbox.

## 5. Shared knowledge and the librarian (3 min)
Ask a question about your project. Show the answer cites `knowledge/<file>.md`.
Open `knowledge/index.md` (read first, "read it when"), then `agents/librarian.md` (Haiku, read-only on shared, writes only to personal). Show `~/.claude/team-os/personal/`: private, own git repo, secret scan on commit.

## 6. A ticket to a draft PR (5 min) — `/team-os:implement-ticket <ID>`
Narrate each phase: ticket fetched from Jira, plan shown for approval, `coder` subagent implements, tests run, draft PR opened, self-review checklist.
Open `skills/implement-ticket/SKILL.md` and `agents/coder.md`. Point out that workflows are just reviewed Markdown.
Backup if the connector misbehaves: paste the ticket text; the skill continues.

## 7. Update without reinstalling (2 min)
In the second clone: add `policy/rules/deny-<something>.json`, commit, push. In the demo clone: `git pull`. Show the new rule now in `~/.claude/settings.json`. Open `bin/refresh.sh` and the `post-merge` hook. The version in the status line changes.

## 8. Status line and the session banner (1 min)
Point at the status line (model, context %, version). Open `hooks/statusline.sh`: JSON on stdin, one line out; yellow at 70%, red at 90%.

## 9. Reversible (1 min) — `./uninstall.sh`
Show settings restored, personal notes kept. Re-run `./install.sh` to show it is idempotent.

## 10. Tests and architecture (1 min)
Run `bin/test.sh`. Open `docs/ARCHITECTURE.md` for the layers, data flows and trade-offs.

## 11. The ask (1 min)
Pilot with 3-5 engineers for two weeks. Measure: time to onboard, PRs opened through the workflow, guardrail blocks, feedback. Then the roadmap: debug and PR-review skills, Sentry connector, more agents, scheduled routines, Windows installer, CI check that agent model pins match policy, a `contribute` command to promote personal notes into the shared bundle.

## If something goes wrong
| Problem | Recovery |
|---|---|
| `claude plugin ...` subcommand fails | The installer prints the manual `/plugin marketplace add <path>` and `/plugin install team-os@teamdata` commands; run them in Claude Code |
| Plugin not showing after install | Fully exit and restart Claude Code; run `/plugin` to list |
| Guard did not fire | Check `/hooks`, confirm the plugin is enabled, restart the session |
| Jira connector not connected | Paste the ticket text into the chat |
| Live demo impossible | Run `bin/test.sh` and walk the code instead; the tests demonstrate every mechanism |
