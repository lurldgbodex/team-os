#!/usr/bin/env bash
# Shared helpers for the Team OS scripts. Source this file, do not run it.
# The variables below are used by the scripts that source this file.
# shellcheck disable=SC2034

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKETPLACE_NAME="teamdata"
PLUGIN_NAME="team-os"

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
STATE_DIR="$CLAUDE_HOME/team-os"
CONFIG_FILE="$STATE_DIR/config.env"
PERSONAL_DIR="$STATE_DIR/personal"
SETTINGS="$CLAUDE_HOME/settings.json"
LOG_FILE="$STATE_DIR/install.log"

# Enforced mode: one Team OS-owned drop-in in Claude Code's managed settings.
# Claude Code reads managed-settings.d/*.json in alphabetical order, so our file
# sits beside any other admin policy instead of replacing it.
case "$(uname -s)" in
  Darwin) MANAGED_DIR_DEFAULT="/Library/Application Support/ClaudeCode" ;;
  *)      MANAGED_DIR_DEFAULT="/etc/claude-code" ;;
esac
MANAGED_DIR="${TEAM_OS_MANAGED_DIR:-$MANAGED_DIR_DEFAULT}"
MANAGED_DROPIN_DIR="$MANAGED_DIR/managed-settings.d"
MANAGED_FILE="$MANAGED_DROPIN_DIR/50-team-os.json"

# Set TEAM_OS_SKIP_CLAUDE=1 to skip every call to the claude CLI (used by tests).
SKIP_CLAUDE="${TEAM_OS_SKIP_CLAUDE:-0}"

if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""; C_OFF=""
fi

log()  { mkdir -p "$STATE_DIR"; printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "$LOG_FILE"; }
say()  { printf '%s\n' "$*"; log "$*"; }
ok()   { printf '%s✓%s %s\n' "$C_GREEN" "$C_OFF" "$*"; log "ok: $*"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; log "warn: $*"; }
die()  { printf '%s✗%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; log "error: $*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# True if we can create or replace MANAGED_FILE without admin rights: the
# drop-in dir if it exists, else the nearest existing parent (we mkdir -p it).
managed_writable() {
  local d="$MANAGED_DROPIN_DIR"
  while [ ! -d "$d" ]; do d="$(dirname "$d")"; done
  [ -w "$d" ]
}

# Run a claude CLI command unless skipped. Failures are reported, not fatal:
# the plugin commands differ slightly between Claude Code versions.
run_claude() {
  if [ "$SKIP_CLAUDE" = "1" ]; then
    log "skipped (TEAM_OS_SKIP_CLAUDE): claude $*"
    return 0
  fi
  if claude "$@" >>"$LOG_FILE" 2>&1; then
    return 0
  fi
  return 1
}

load_config() {
  # shellcheck disable=SC1090
  [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
  return 0
}

save_config() {
  # $1 = KEY, $2 = value. Updates or appends KEY=value in config.env.
  mkdir -p "$STATE_DIR"
  touch "$CONFIG_FILE"
  if grep -q "^$1=" "$CONFIG_FILE"; then
    local tmp; tmp="$(mktemp)"
    grep -v "^$1=" "$CONFIG_FILE" > "$tmp"
    mv "$tmp" "$CONFIG_FILE"
  fi
  printf '%s=%q\n' "$1" "$2" >> "$CONFIG_FILE"
}
