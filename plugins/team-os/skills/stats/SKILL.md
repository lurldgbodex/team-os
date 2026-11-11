---
name: stats
description: Show Team OS guard blocks by rule and by week from the local audit log, and your pull requests that close an issue. Read-only. Use when the engineer asks for Team OS stats, pilot metrics or how often the guard blocks.
argument-hint: "[weeks, default 8]"
---

# Team OS stats

Show how often the guard blocks and how many of your PRs close an issue. This skill is read-only: never edit or delete the audit file, and never send it anywhere.

Let N be the number of weeks from the argument (default 8).

1. **Guard blocks**: run `bash <base>/stats.sh <N>`, where `<base>` is this skill's base directory (shown above as "Base directory for this skill"). It reads `${CLAUDE_HOME:-$HOME/.claude}/team-os/audit.jsonl`, skips malformed lines, and prints blocks per rule (most first), per ISO week and the top 5 repos for the last N weeks. If it says "No guard blocks recorded yet", go to step 3.
2. **Read-only**: do not edit or delete the audit file.
3. **Pull requests** in the current repo: `gh pr list --author @me --state all --limit 200 --json number,title,state,body,createdAt`. Keep the PRs whose body contains `Closes #` (any letter case, so also `closes #`). Count them by state (open, merged, closed) and list the last 10 with number, title and state. If this is not a GitHub repo or `gh` is not logged in, say so and skip this step.
4. **Output** two short tables, then one line of interpretation:
   - Table 1: blocks by rule, with a column per week or a separate by-week line.
   - Table 2: PRs that close an issue, by state, plus the last 10.
   - Interpretation: for example, a rule with many blocks may be too strict or may show a habit worth changing, so suggest reviewing it. Do not change any rule or file.
