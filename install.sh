#!/usr/bin/env bash
# Team OS installer (macOS / Linux). Short on purpose: read it before you run it.
#
#   ./install.sh                  interactive
#   ./install.sh --yes            accept all defaults
#   ./install.sh --status-line team|keep
#
# What it does, in order:
#   1. checks prerequisites (claude, git, gh, jq; gitleaks optional)
#   2. saves where this checkout lives (so hooks can report the version)
#   3. registers this folder as a Claude Code plugin marketplace and installs the plugin
#   4. adds a post-merge git hook so `git pull` refreshes everything
#   5. creates your private personal/ notes folder (own git repo, secret-scan hook)
#   6. applies the team deny/ask rules and behaviour rules (reversible)
#   7. installs the status line (unless you keep your own)
#
# Everything it touches is appended to ~/.claude/team-os/install.log.
# ./uninstall.sh reverses all of it and keeps your personal notes.

set -euo pipefail
# shellcheck source=bin/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/lib.sh"

ASSUME_YES=0
STATUS_LINE_CHOICE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1 ;;
    --status-line) shift; STATUS_LINE_CHOICE="${1:-}" ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

mkdir -p "$STATE_DIR"
say "Installing Team OS from $REPO_DIR"

# --- 1. prerequisites -----------------------------------------------------
if [ "$SKIP_CLAUDE" != "1" ]; then
  have claude || die "Claude Code is not installed. See https://code.claude.com/docs and re-run."
fi
have git || die "git is required."

if ! have jq; then
  say "jq is missing, trying to install it..."
  if   have brew;    then brew install jq
  elif have apt-get; then sudo apt-get install -y jq
  elif have dnf;     then sudo dnf install -y jq
  else die "jq is required. Install it (https://jqlang.org) and re-run."; fi
fi
ok "jq, git found"

if have gh; then
  gh auth status >/dev/null 2>&1 && ok "gh is logged in" || warn "gh is installed but not logged in: run 'gh auth login'"
else
  warn "gh (GitHub CLI) not found. Needed for /team-os:implement-ticket to open pull requests."
fi
have gitleaks && ok "gitleaks found" || warn "gitleaks not found (optional). Your personal notes folder will warn instead of blocking secrets."

# --- 2. remember where this checkout lives -----------------------------------
save_config REPO_DIR "$REPO_DIR"
ok "recorded checkout location"

# --- 3. marketplace + plugin ------------------------------------------------
if have claude && [ "$SKIP_CLAUDE" != "1" ]; then
  run_claude plugin marketplace add "$REPO_DIR" || \
    run_claude plugin marketplace update "$MARKETPLACE_NAME" || \
    warn "could not register the marketplace. In Claude Code run: /plugin marketplace add $REPO_DIR"
  run_claude plugin install "${PLUGIN_NAME}@${MARKETPLACE_NAME}" || \
    warn "could not install the plugin. In Claude Code run: /plugin install ${PLUGIN_NAME}@${MARKETPLACE_NAME}"
  ok "marketplace '$MARKETPLACE_NAME' registered, plugin '$PLUGIN_NAME' installed"
else
  warn "skipped plugin install (Claude CLI not used)"
fi

# --- 4. post-merge hook ---------------------------------------------------------
if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  hook="$(git -C "$REPO_DIR" rev-parse --git-path hooks/post-merge)"
  case "$hook" in /*) ;; *) hook="$REPO_DIR/$hook" ;; esac
  mkdir -p "$(dirname "$hook")"
  if [ -f "$hook" ] && ! grep -q "team-os" "$hook"; then
    warn "a post-merge hook already exists; not overwriting it. Run ./update.sh to refresh manually."
  else
    cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
# team-os post-merge hook: refresh plugin + rules after every git pull.
[ "${TEAM_OS_IN_UPDATE:-0}" = "1" ] && exit 0
exec "$(git rev-parse --show-toplevel)/bin/refresh.sh"
HOOK
    chmod +x "$hook"
    ok "post-merge hook installed (git pull now refreshes Team OS)"
  fi
else
  warn "this folder is not a git checkout, so git pull auto-refresh is unavailable"
fi

# --- 5. personal folder -----------------------------------------------------------
if [ ! -d "$PERSONAL_DIR/.git" ]; then
  mkdir -p "$PERSONAL_DIR"
  git -C "$PERSONAL_DIR" init -q
  cat > "$PERSONAL_DIR/README.md" <<'EOF'
# Personal Team OS notes

Private to this machine. Your assistant writes project notes, handoffs and routines here.
Never pushed to the shared repo. To back it up, push it to a PRIVATE repo you own.
EOF
  cat > "$PERSONAL_DIR/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
# Block commits that contain secret-looking strings (needs gitleaks).
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks protect --staged --redact -v || { echo "pre-commit: possible secret found, commit blocked." >&2; exit 1; }
else
  echo "pre-commit: gitleaks not installed, skipping secret scan. Install it before pushing anywhere." >&2
fi
exit 0
EOF
  chmod +x "$PERSONAL_DIR/.git/hooks/pre-commit"
  ok "personal notes folder created at $PERSONAL_DIR"
else
  ok "personal notes folder already exists (left unchanged)"
fi

# --- 6. policy --------------------------------------------------------------------
"$REPO_DIR/bin/apply-policy.sh"

# --- 7. status line ----------------------------------------------------------------
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
existing="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
ours="$REPO_DIR/plugins/team-os/hooks/statusline.sh"
choice="$STATUS_LINE_CHOICE"
if [ -z "$choice" ]; then
  if [ -z "$existing" ] || [ "$existing" = "$ours" ]; then
    choice="team"
  elif [ "$ASSUME_YES" = "1" ]; then
    choice="keep"
  else
    printf 'You already have a status line (%s). Replace it with Team OS'"'"'s? [y/N] ' "$existing"
    read -r answer || answer="n"
    case "$answer" in y|Y|yes) choice="team" ;; *) choice="keep" ;; esac
  fi
fi
if [ "$choice" = "team" ]; then
  if [ -n "$existing" ] && [ "$existing" != "$ours" ]; then
    save_config PREVIOUS_STATUSLINE "$(jq -c '.statusLine' "$SETTINGS")"
  fi
  tmp="$(mktemp "$SETTINGS.XXXXXX")"
  jq --arg cmd "$ours" '.statusLine = {type: "command", command: $cmd}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  save_config STATUSLINE_INSTALLED 1
  ok "status line installed"
else
  ok "kept your existing status line"
fi

echo
ok "Team OS installed."
say "Next: exit Claude Code and start it again so hooks and the status line load."
say "Then try: /team-os:setup"
