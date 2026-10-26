#!/usr/bin/env bash
# Repo hygiene check: run before every pull request (and in CI).
# Fails if any JSON is invalid, a script is not executable or does not parse,
# a policy rule is missing its explanation, or an agent/skill lacks frontmatter.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
bad() { printf '✗ %s\n' "$*" >&2; fail=1; }

# 1. JSON files parse
while IFS= read -r f; do
  jq empty "$f" 2>/dev/null || bad "invalid JSON: ${f#"$ROOT"/}"
done < <(find "$ROOT" -name '*.json' -not -path '*/.git/*')

# 2. Shell scripts: executable and syntactically valid
while IFS= read -r f; do
  [ -x "$f" ] || bad "not executable: ${f#"$ROOT"/}"
  bash -n "$f" 2>/dev/null || bad "syntax error: ${f#"$ROOT"/}"
done < <(find "$ROOT" -name '*.sh' -not -path '*/.git/*')

# 3. Policy rules are explained and owned
for f in "$ROOT"/plugins/team-os/policy/rules/*.json; do
  jq -e '.id and .type and .rule and .why and .owner' "$f" >/dev/null 2>&1 \
    || bad "rule missing id/type/rule/why/owner: ${f#"$ROOT"/}"
  id="$(jq -r .id "$f" 2>/dev/null)"
  [ "$id" = "$(basename "$f" .json)" ] || bad "rule id does not match file name: ${f#"$ROOT"/}"
done

# 4. Agents and skills have frontmatter with name and description
for f in "$ROOT"/plugins/team-os/agents/*.md "$ROOT"/plugins/team-os/skills/*/SKILL.md; do
  head -1 "$f" | grep -q '^---$' || bad "no frontmatter: ${f#"$ROOT"/}"
  grep -q '^name:' "$f"        || bad "no name: ${f#"$ROOT"/}"
  grep -q '^description:' "$f" || bad "no description: ${f#"$ROOT"/}"
done

# 5. Every knowledge file is listed in the index
for f in "$ROOT"/plugins/team-os/knowledge/*.md; do
  b="$(basename "$f")"
  [ "$b" = "index.md" ] && continue
  grep -q "$b" "$ROOT/plugins/team-os/knowledge/index.md" || bad "knowledge file not in index.md: $b"
done

# 6. Plugin and marketplace versions agree
pv="$(jq -r .version "$ROOT/plugins/team-os/.claude-plugin/plugin.json")"
mv="$(jq -r '.plugins[0].version' "$ROOT/.claude-plugin/marketplace.json")"
[ "$pv" = "$mv" ] || bad "plugin.json version ($pv) != marketplace.json version ($mv)"

[ "$fail" -eq 0 ] && echo "✓ hygiene check passed"
exit "$fail"
