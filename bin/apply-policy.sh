#!/usr/bin/env bash
# Merge Team OS policy into the engineer's own Claude settings, reversibly.
#
#   apply-policy.sh            apply (idempotent)
#   apply-policy.sh --remove   take out everything Team OS added
#   apply-policy.sh --list     print the current rules as a table
#
# Environment overrides (used by tests):
#   CLAUDE_HOME   default ~/.claude
#
# What it touches:
#   $CLAUDE_HOME/settings.json            permissions.deny / permissions.ask
#   $CLAUDE_HOME/CLAUDE.md                one marked block of behaviour rules
#   $CLAUDE_HOME/team-os/managed-rules.json   what we added (so removal is exact)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
POLICY_DIR="$REPO_DIR/plugins/team-os/policy"

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SETTINGS="$CLAUDE_HOME/settings.json"
CLAUDE_MD="$CLAUDE_HOME/CLAUDE.md"
STATE_DIR="$CLAUDE_HOME/team-os"
MANAGED="$STATE_DIR/managed-rules.json"

BEGIN_MARK="<!-- team-os:begin (managed by Team OS, do not edit; run /team-os:rules or uninstall.sh) -->"
END_MARK="<!-- team-os:end -->"

command -v jq >/dev/null 2>&1 || { echo "apply-policy: jq is required" >&2; exit 1; }

mode="apply"
case "${1:-}" in
  --remove) mode="remove" ;;
  --list)   mode="list" ;;
  "")       ;;
  *) echo "usage: $0 [--remove|--list]" >&2; exit 2 ;;
esac

# --- list ---------------------------------------------------------------
if [ "$mode" = "list" ]; then
  printf '%-26s %-6s %-30s %-10s %s\n' ID TYPE RULE OWNER WHY
  for f in "$POLICY_DIR"/rules/*.json; do
    jq -r '[.id, .type, .rule, .owner, .why] | @tsv' "$f" |
      awk -F'\t' '{ printf "%-26s %-6s %-30s %-10s %s\n", $1, $2, $3, $4, $5 }'
  done
  echo
  echo "Behaviour rules:"
  for f in "$POLICY_DIR"/behaviour/*.md; do
    printf '  - %s: %s' "$(basename "$f" .md)" "$(cat "$f")"
  done
  exit 0
fi

mkdir -p "$CLAUDE_HOME" "$STATE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" 2>/dev/null || { echo "apply-policy: $SETTINGS is not valid JSON, not touching it" >&2; exit 1; }

# --- helpers --------------------------------------------------------------
write_settings() {
  # $1 = jq filter, extra args follow. Writes atomically.
  local filter="$1"; shift
  local tmp
  tmp="$(mktemp "$SETTINGS.XXXXXX")"
  jq "$@" "$filter" "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
}

strip_block() {
  # Remove our marked block from CLAUDE.md, leave the rest untouched.
  [ -f "$CLAUDE_MD" ] || return 0
  local tmp
  tmp="$(mktemp "$CLAUDE_MD.XXXXXX")"
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  ' "$CLAUDE_MD" > "$tmp"
  # Drop trailing blank lines left behind
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp" 2>/dev/null || true
  if [ -s "$tmp" ]; then mv "$tmp" "$CLAUDE_MD"; else rm -f "$tmp" "$CLAUDE_MD"; fi
}

remove_managed_permissions() {
  [ -f "$MANAGED" ] || return 0
  write_settings '
    ($m[0].deny // []) as $d | ($m[0].ask // []) as $a |
    .permissions.deny = ((.permissions.deny // []) - $d) |
    .permissions.ask  = ((.permissions.ask  // []) - $a) |
    if (.permissions.deny | length) == 0 then del(.permissions.deny) else . end |
    if (.permissions.ask  | length) == 0 then del(.permissions.ask)  else . end |
    if (.permissions | length) == 0 then del(.permissions) else . end
  ' --slurpfile m "$MANAGED"
}

# --- remove ---------------------------------------------------------------
if [ "$mode" = "remove" ]; then
  remove_managed_permissions
  strip_block
  rm -f "$MANAGED"
  echo "Team OS rules removed."
  exit 0
fi

# --- apply ----------------------------------------------------------------
# Start from a clean slate for *our* rules so rule changes (edited or deleted
# files) propagate, then add the current set. Rules the engineer already had
# are never in $MANAGED, so they are never removed.
remove_managed_permissions

deny_json="$(for f in "$POLICY_DIR"/rules/*.json; do jq -r 'select(.type=="deny") | .rule' "$f"; done | jq -R . | jq -s .)"
ask_json="$(for f in "$POLICY_DIR"/rules/*.json; do jq -r 'select(.type=="ask") | .rule' "$f"; done | jq -R . | jq -s .)"

# Record only rules that were not already present before us, so removal never
# takes out something the engineer configured themselves.
new_deny="$(jq -n --argjson want "$deny_json" --slurpfile s "$SETTINGS" '$want - ($s[0].permissions.deny // [])')"
new_ask="$(jq -n --argjson want "$ask_json"  --slurpfile s "$SETTINGS" '$want - ($s[0].permissions.ask  // [])')"

write_settings '
  .permissions.deny = ((.permissions.deny // []) + $d | unique) |
  .permissions.ask  = ((.permissions.ask  // []) + $a | unique)
' --argjson d "$new_deny" --argjson a "$new_ask"

jq -n --argjson d "$new_deny" --argjson a "$new_ask" '{deny: $d, ask: $a}' > "$MANAGED"

# Behaviour rules -> one marked block in CLAUDE.md
strip_block
{
  [ -s "$CLAUDE_MD" ] && echo
  echo "$BEGIN_MARK"
  echo "# Team OS behaviour rules"
  for f in "$POLICY_DIR"/behaviour/*.md; do
    printf -- '- %s\n' "$(tr '\n' ' ' < "$f" | sed 's/ *$//')"
  done
  echo "$END_MARK"
} >> "$CLAUDE_MD"

echo "Team OS rules applied: $(jq 'length' <<<"$new_deny") deny, $(jq 'length' <<<"$new_ask") ask (new), behaviour block written."
