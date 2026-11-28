#!/usr/bin/env bash
# Refresh the plugin and policy from the current checkout.
# Called by update.sh and by the post-merge git hook (so a plain `git pull`
# delivers new rules and agents without re-running the installer).

set -u
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mkdir -p "$STATE_DIR"

if have claude; then
  run_claude plugin marketplace update "$MARKETPLACE_NAME" || warn "could not refresh the marketplace (see $LOG_FILE)"
  run_claude plugin update "${PLUGIN_NAME}@${MARKETPLACE_NAME}" || warn "could not update the plugin (see $LOG_FILE)"
elif [ "$SKIP_CLAUDE" != "1" ]; then
  warn "claude CLI not found, skipped plugin refresh"
fi

"$REPO_DIR/bin/apply-policy.sh" || warn "policy apply failed"

# Enforced mode is active when our managed file exists. Never sudo here: this
# can run from a git hook, so just say what to run.
if [ -f "$MANAGED_FILE" ] && ! "$REPO_DIR/bin/apply-policy.sh" --enforced --check; then
  if managed_writable; then
    "$REPO_DIR/bin/apply-policy.sh" --enforced || warn "enforced rules update failed"
  else
    warn "enforced rules in $MANAGED_FILE are out of date. Run: $(enforced_sudo_cmd --enforced)"
  fi
fi

version="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
ok "Team OS refreshed at ${version}. New Claude Code sessions will use it."
