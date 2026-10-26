# Team OS policy

Every rule is one small file, so a change is a small, reviewable pull request.

## Permission rules: `rules/*.json`

```json
{
  "id": "deny-cdk-deploy",
  "type": "deny",
  "rule": "Bash(cdk deploy:*)",
  "why": "Infrastructure deploys run in CI with review.",
  "owner": "devops"
}
```

| Field | Meaning |
|---|---|
| `id` | Unique name, matches the file name |
| `type` | `deny` (always blocked) or `ask` (Claude must ask first) |
| `rule` | A Claude Code permission rule, for example `Bash(git push:*)` |
| `why` | One sentence explaining the rule. Required, so rules stay justified |
| `owner` | Team or person who maintains the rule |

## Behaviour rules: `behaviour/*.md`

One short Markdown file per always-on instruction (one or two sentences each).

## How they reach an engineer's machine

`bin/apply-policy.sh` merges them into the engineer's own Claude settings:

- Permission rules are added to `~/.claude/settings.json` (`permissions.deny` / `permissions.ask`). Rules the engineer already had are never removed.
- Behaviour rules are written into a marked block in `~/.claude/CLAUDE.md`.
- The ids of everything Team OS added are recorded in `~/.claude/team-os/managed-rules.json`, so removal takes out only Team OS rules.

Applying twice changes nothing (idempotent). `./uninstall.sh` or `bin/apply-policy.sh --remove` takes everything back out.

## Current rules

Run `bin/apply-policy.sh --list` to print the live table.
