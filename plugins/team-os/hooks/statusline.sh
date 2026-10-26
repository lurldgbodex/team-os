#!/usr/bin/env bash
# Status line: shows model, context use and Team OS version.
#
# Claude Code pipes a JSON object with session data to this script on stdin
# and displays whatever the script prints. Fields used here:
#   .model.display_name
#   .context_window.used_percentage
# Usage / rate-limit fields exist in newer versions; they are read
# defensively and only shown when present.

set -u

input="$(cat)"
command -v jq >/dev/null 2>&1 || { echo "Team OS"; exit 0; }

model="$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "?"')"
ctx="$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')"
five="$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')"
seven="$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')"

# Version = short git commit of the Team OS checkout.
CONFIG="${HOME}/.claude/team-os/config.env"
REPO_DIR=""
[ -f "$CONFIG" ] && . "$CONFIG"
version="$(git -C "${REPO_DIR:-.}" rev-parse --short HEAD 2>/dev/null || echo dev)"

GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'

# Colour by threshold: yellow from 70%, red from 90%.
colour_for() {
  local pct="${1%.*}"
  if   [ "$pct" -ge 90 ]; then printf '%s' "$RED"
  elif [ "$pct" -ge 70 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

out="${model}"

if [ -n "$ctx" ]; then
  c="$(colour_for "$ctx")"
  out="${out} ${DIM}·${RESET} ctx ${c}${ctx%.*}%${RESET}"
fi

if [ -n "$five" ]; then
  c="$(colour_for "$five")"
  out="${out} ${DIM}·${RESET} 5h ${c}${five%.*}%${RESET}"
fi

if [ -n "$seven" ]; then
  c="$(colour_for "$seven")"
  out="${out} ${DIM}·${RESET} 7d ${c}${seven%.*}%${RESET}"
fi

out="${out} ${DIM}·${RESET} Team OS ${version}"
printf '%s\n' "$out"
