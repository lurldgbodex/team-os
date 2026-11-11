#!/usr/bin/env bash
# Print guard blocks by rule, by ISO week and top repos for the last N weeks.
# Usage: stats.sh [weeks]   (default 8). Read-only: never writes the audit file.
set -u

FILE="${CLAUDE_HOME:-$HOME/.claude}/team-os/audit.jsonl"
N="${1:-8}"
# TEAM_OS_NOW (epoch seconds) is for tests, so they do not depend on the real clock.
NOW="${TEAM_OS_NOW:-$(date +%s)}"

if [ ! -s "$FILE" ]; then
  echo "No guard blocks recorded yet"
  exit 0
fi

# Lines that parse and fall in the window; malformed lines are skipped.
RECENT="$(jq -R 'fromjson? // empty' "$FILE" \
  | jq -c --argjson n "$N" --argjson now "$NOW" \
    'select((.ts? | fromdateiso8601?) >= ($now - $n * 604800))')"

if [ -z "$RECENT" ]; then
  echo "No guard blocks in the last $N weeks"
  exit 0
fi

echo "Guard blocks in the last $N weeks"
echo "By rule:"
printf '%s\n' "$RECENT" | jq -r '.rule' | sort | uniq -c | sort -rn
echo "By week:"
printf '%s\n' "$RECENT" \
  | jq -r '.ts | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%G-W%V")' | sort | uniq -c
echo "Top repos:"
printf '%s\n' "$RECENT" | jq -r '.repo // "(none)"' | sort | uniq -c | sort -rn | head -5
