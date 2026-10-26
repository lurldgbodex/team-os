#!/usr/bin/env bash
# Reverse everything install.sh did. Keeps your personal notes folder.
set -u
# shellcheck source=bin/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/lib.sh"

load_config

# Rules and behaviour block
"$REPO_DIR/bin/apply-policy.sh" --remove || warn "could not remove rules"

# Status line: only touch it if we installed it
if [ "${STATUSLINE_INSTALLED:-0}" = "1" ] && [ -f "$SETTINGS" ]; then
  ours="$REPO_DIR/plugins/team-os/hooks/statusline.sh"
  current="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
  if [ "$current" = "$ours" ]; then
    tmp="$(mktemp "$SETTINGS.XXXXXX")"
    if [ -n "${PREVIOUS_STATUSLINE:-}" ]; then
      jq --argjson prev "$PREVIOUS_STATUSLINE" '.statusLine = $prev' "$SETTINGS" > "$tmp"
    else
      jq 'del(.statusLine)' "$SETTINGS" > "$tmp"
    fi
    mv "$tmp" "$SETTINGS"
    ok "status line restored"
  fi
fi

# post-merge hook: only remove ours
if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  hook="$(git -C "$REPO_DIR" rev-parse --git-path hooks/post-merge)"
  case "$hook" in /*) ;; *) hook="$REPO_DIR/$hook" ;; esac
  if [ -f "$hook" ] && grep -q "team-os" "$hook"; then
    rm -f "$hook"
    ok "post-merge hook removed"
  fi
fi

# Plugin and marketplace
if have claude && [ "$SKIP_CLAUDE" != "1" ]; then
  run_claude plugin uninstall "${PLUGIN_NAME}@${MARKETPLACE_NAME}" || warn "could not uninstall the plugin"
  run_claude plugin marketplace remove "$MARKETPLACE_NAME" || warn "could not remove the marketplace"
fi

# Config (keep the personal folder and the log)
rm -f "$CONFIG_FILE"

ok "Team OS uninstalled. Your personal notes are kept at $PERSONAL_DIR"
