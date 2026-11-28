#!/usr/bin/env bash
# Merge Team OS policy into the engineer's own Claude settings, reversibly.
#
#   apply-policy.sh            apply (idempotent)
#   apply-policy.sh --remove   take out everything Team OS added
#   apply-policy.sh --list     print the current rules as a table
#   apply-policy.sh --enforced [--remove|--check]
#                              write, delete or verify the managed-settings file
#
# Environment overrides (used by tests):
#   CLAUDE_HOME            default ~/.claude
#   TEAM_OS_MANAGED_DIR    managed settings dir, default /etc/claude-code
#                          (macOS: /Library/Application Support/ClaudeCode)
#
# What it touches:
#   $CLAUDE_HOME/settings.json            permissions.deny / permissions.ask
#   $CLAUDE_HOME/CLAUDE.md                one marked block of behaviour rules
#   $CLAUDE_HOME/team-os/managed-rules.json   what we added (so removal is exact)
#
# --enforced touches only <managed dir>/managed-settings.d/50-team-os.json (deny/ask
# rules, marketplace, enabled plugin). It may run as root, so it never writes
# under $CLAUDE_HOME.

set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
POLICY_DIR="$REPO_DIR/plugins/team-os/policy"

CLAUDE_MD="$CLAUDE_HOME/CLAUDE.md"
MANAGED="$STATE_DIR/managed-rules.json"

BEGIN_MARK="<!-- team-os:begin (managed by Team OS, do not edit; run /team-os:rules or uninstall.sh) -->"
END_MARK="<!-- team-os:end -->"

command -v jq >/dev/null 2>&1 || { echo "apply-policy: jq is required" >&2; exit 1; }

usage() { echo "usage: $0 [--remove|--list|--enforced [--remove|--check]]" >&2; exit 2; }

mode="apply"
case "${1:-}" in
  --remove) mode="remove" ;;
  --list)   mode="list" ;;
  --enforced)
    case "${2:-}" in
      "")       mode="enforced" ;;
      --remove) mode="enforced-remove" ;;
      --check)  mode="enforced-check" ;;
      *) usage ;;
    esac ;;
  "")       ;;
  *) usage ;;
esac

rules_of() {
  # $1 = deny|ask. Prints the rule strings from policy/rules/*.json as a JSON array.
  for f in "$POLICY_DIR"/rules/*.json; do jq -r --arg t "$1" 'select(.type==$t) | .rule' "$f"; done | jq -R . | jq -s .
}

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

# --- enforced -------------------------------------------------------------
# Nothing below this block runs in enforced mode: it must not create files in
# a home directory, because it may run as root.
if [ "${mode#enforced}" != "$mode" ]; then
  enforced_json() {
    jq -n --argjson d "$(rules_of deny)" --argjson a "$(rules_of ask)" \
      --arg repo "$REPO_DIR" --arg mp "$MARKETPLACE_NAME" --arg pl "$PLUGIN_NAME" '{
        permissions: {deny: $d, ask: $a},
        extraKnownMarketplaces: {($mp): {source: {source: "directory", path: $repo}}},
        enabledPlugins: {"\($pl)@\($mp)": true}
      }'
  }
  need_admin() {
    echo "apply-policy: no write access to $MANAGED_DROPIN_DIR. Enforced mode needs admin rights. Run: sudo $REPO_DIR/bin/apply-policy.sh $*" >&2
    exit 1
  }

  case "$mode" in
    enforced-check)
      if [ -f "$MANAGED_FILE" ] && [ "$(jq -S . "$MANAGED_FILE" 2>/dev/null)" = "$(enforced_json | jq -S .)" ]; then exit 0; fi
      exit 1 ;;
    enforced-remove)
      [ -f "$MANAGED_FILE" ] || { echo "No enforced rules to remove ($MANAGED_FILE does not exist)."; exit 0; }
      managed_writable || need_admin --enforced --remove
      rm -f "$MANAGED_FILE"
      echo "Team OS enforced rules removed from $MANAGED_FILE."
      exit 0 ;;
  esac

  managed_writable || need_admin --enforced
  content="$(enforced_json)"
  mkdir -p "$MANAGED_DROPIN_DIR"
  # Hidden temp name: Claude Code ignores dotfiles, so it never reads a half-written file.
  tmp="$(mktemp "$MANAGED_DROPIN_DIR/.team-os.XXXXXX")"
  printf '%s\n' "$content" > "$tmp"
  chmod 644 "$tmp"   # mktemp makes it 600; every user's sessions must be able to read it
  mv "$tmp" "$MANAGED_FILE"
  echo "Team OS enforced rules written to $MANAGED_FILE: $(jq '.permissions.deny | length' <<<"$content") deny, $(jq '.permissions.ask | length' <<<"$content") ask."
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

deny_json="$(rules_of deny)"
ask_json="$(rules_of ask)"

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
