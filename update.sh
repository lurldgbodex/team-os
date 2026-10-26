#!/usr/bin/env bash
# Pull the latest Team OS and refresh the plugin and rules.
# A plain `git pull` in this folder does the same through the post-merge hook.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# Tell the post-merge hook not to refresh a second time during this pull.
TEAM_OS_IN_UPDATE=1 git pull --ff-only
exec ./bin/refresh.sh
