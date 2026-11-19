#!/usr/bin/env bash
# SessionStart hook: tell the engineer (and Claude) which Team OS version is
# running, and warn when the checkout is behind its upstream branch.
#
# Whatever this script prints to stdout is added to the session context.
# The "version" is simply the git commit of the Team OS checkout.

set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# The plugin lives at <repo>/plugins/team-os, so the repo is two levels up.
# When installed from a marketplace Claude Code may copy the plugin into a
# cache, so we also read the repo location the installer saved.
CONFIG="${HOME}/.claude/team-os/config.env"
REPO_DIR=""
if [ -f "$CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi
[ -z "${REPO_DIR:-}" ] && REPO_DIR="$(cd "$PLUGIN_ROOT/../.." 2>/dev/null && pwd)"

version="unknown"
behind_note=""

if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  version="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"

  upstream="$(git -C "$REPO_DIR" rev-parse --abbrev-ref '@{u}' 2>/dev/null || true)"
  if [ -n "$upstream" ]; then
    # Compare against what we last fetched. No network call here: keeps
    # session start fast. update.sh and git pull keep the ref fresh.
    behind="$(git -C "$REPO_DIR" rev-list --count "HEAD..${upstream}" 2>/dev/null || echo 0)"
    if [ "${behind:-0}" -gt 0 ]; then
      behind_note=" Your checkout is ${behind} commit(s) behind ${upstream}. Run ./update.sh (or git pull) in ${REPO_DIR} to get new rules and agents."
    fi
  fi
fi

echo "Team OS · ${version}.${behind_note}"

# Print "owner/repo" for the GitHub repo the engineer is working in. Prints
# nothing outside a git work tree, in the Team OS checkout itself, or when
# origin is not on github.com.
current_github_repo() {
  local dir top team_top url path
  dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$top" ] || return 0
  top="$(cd "$top" && pwd -P)" || return 0
  team_top="$(cd "$REPO_DIR" 2>/dev/null && pwd -P)" || team_top=""
  [ "$top" = "$team_top" ] && return 0

  url="$(git -C "$top" remote get-url origin 2>/dev/null)" || return 0
  case "$url" in
    https://github.com/*) path="${url#https://github.com/}" ;;
    git@github.com:*) path="${url#git@github.com:}" ;;
    ssh://git@github.com/*) path="${url#ssh://git@github.com/}" ;;
    *) return 0 ;;
  esac
  path="${path%/}"
  path="${path%.git}"
  case "$path" in
    */*/* | */ | /* | "") return 0 ;;
    */*) printf '%s\n' "$path" ;;
  esac
}

# Succeed when a note's frontmatter has a "repos:" entry equal to $1
# (case-insensitive, whole item). Reads file names, one per line, on stdin.
# Supports "repos: [a/b, c/d]" and a block list of "- a/b" lines.
notes_list_repo() {
  local target="$1" file
  while IFS= read -r file; do
    awk -v target="$target" '
      function check(item) {
        gsub(/^[ \t]+|[ \t]+$/, "", item)
        gsub(/^["\047]|["\047]$/, "", item)
        if (tolower(item) == target) found = 1
      }
      function check_inline(text,   n, parts, i) {
        gsub(/[][]/, "", text)
        n = split(text, parts, ",")
        for (i = 1; i <= n; i++) check(parts[i])
      }
      { sub(/\r$/, "") }
      FNR == 1 { state = ($0 == "---") ? 1 : 0; inrepos = 0; found = 0; next }
      state == 0 { next }
      $0 == "---" { if (found) { hit = 1; exit } ; state = 0; next }
      /^repos:/ {
        inrepos = 1
        rest = substr($0, 7)
        sub(/[ \t]+#.*$/, "", rest)
        check_inline(rest)
        next
      }
      inrepos && /^[ \t]*-[ \t]/ {
        item = $0
        sub(/^[ \t]*-[ \t]+/, "", item)
        sub(/[ \t]+#.*$/, "", item)
        check(item)
        next
      }
      inrepos && /^[ \t]*(#.*)?$/ { next }
      { inrepos = 0 }
      END { exit(hit ? 0 : 1) }
    ' "$file" 2>/dev/null && return 0
  done
  return 1
}

# One line suggesting /team-os:onboard-repo when no knowledge page lists the
# repo. No network calls. Any failure just omits the line.
suggest_onboarding() {
  local repo lower personal="${HOME}/.claude/team-os/personal"
  repo="$(current_github_repo)" || return 0
  [ -n "$repo" ] || return 0
  lower="$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')"

  {
    [ -d "$personal" ] && find "$personal" -type f -name '*.md' 2>/dev/null
    find "$PLUGIN_ROOT/knowledge" -maxdepth 1 -type f -name '*.md' 2>/dev/null
  } | notes_list_repo "$lower" && return 0

  echo "No Team OS knowledge page lists ${repo}. Run /team-os:onboard-repo to draft one."
}

suggest_onboarding 2>/dev/null || true
exit 0
