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
exit 0
