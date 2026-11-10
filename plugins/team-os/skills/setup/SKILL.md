---
name: setup
description: Post-install check for Team OS. Verifies prerequisites, connectors, rules and the guard hook, then gives a one-minute tour. Safe to re-run.
---

# Team OS setup check

Run these checks and report a short pass/fail list. Fix nothing without asking.

1. **Version**: run `git -C "${CLAUDE_PLUGIN_ROOT}/../.." rev-parse --short HEAD` and report it.
2. **Tools**: check `git`, `gh` (and `gh auth status`), and `jq` are installed.
3. **Connectors**: run `claude mcp list` and report whether GitHub is connected. If it is missing, tell the engineer to open claude.ai/settings/connectors, connect it, then run `/mcp`. The connector is optional: without it the skills fall back to the `gh` CLI. Do not report Atlassian (Jira) as a problem; the team tracks work in GitHub Issues.
4. **Rules**: read `~/.claude/settings.json` and confirm the Team OS deny/ask rules are present (`jq '.permissions.deny' ~/.claude/settings.json`). These are only the rules from `${CLAUDE_PLUGIN_ROOT}/policy/rules/*.json`; compare against those files. The hard blocks (force pushes, piped installers, production databases, local deploys, secret files) live in the guard hook, not here, so do not report them as missing from settings. Step 6 checks them.
5. **Personal folder**: confirm `~/.claude/team-os/personal/` exists and is a git repo.
6. **Guard hook**: confirm the hard blocks are active.
   - The plugin is enabled: `jq '(.enabledPlugins // {}) | with_entries(select(.key | startswith("team-os@")))' ~/.claude/settings.json` shows a `team-os@…` key set to `true`. An empty `{}` or `false` means it is not enabled here. The plugin can also be enabled in a project's `.claude/settings.json` or `.claude/settings.local.json`, so check those before reporting a failure.
   - The hook is registered: `jq -r '.hooks.PreToolUse[] | "\(.matcher) \(.hooks[].command)"' "${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json"` lists `guard.sh` for `Bash|Read|Edit|Write|Grep`, and `test -x "${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh"` passes.
   - The hook blocks: `printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"/tmp/id_rsa"}}' | "${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh" | jq -r '.hookSpecificOutput.permissionDecision // "allowed"'` prints `deny`.
   - Run exactly that test. Do not test with force-push, `curl | sh` or `.env` text in the command: the live guard blocks the test command itself.
   - If any of these is not as described (other output, empty output or an error), report the guard hook as **FAILED** and name which check failed: plugin not enabled, hook not registered, `guard.sh` not executable, or no `deny`. Do not fix anything without asking.

Then give the one-minute tour:

- Ask any question about our projects. The `librarian` reads the shared knowledge first.
- `/team-os:create-ticket <description>` drafts a GitHub issue and creates it once you approve.
- `/team-os:implement-ticket 42` takes issue #42 to a draft PR that closes it.
- `/team-os:review-pr 57` reviews pull request #57 and can post the findings as a review.
- Dangerous actions (reading `.env`, force pushes, piped installers) are blocked with a reason.
- The status line shows model, context use and Team OS version.
- To update, run `git pull` in the Team OS folder. Rules and the plugin refresh automatically.
