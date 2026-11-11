#!/usr/bin/env bats
# stats.sh reads the audit file and prints guard blocks by rule, week and repo.

bats_require_minimum_version 1.5.0
load test_helper

STATS="$REPO_ROOT/plugins/team-os/skills/stats/stats.sh"
NOW_EPOCH=1794398400 # 2026-11-11T12:00:00Z

setup() {
  export CLAUDE_HOME="$BATS_TEST_TMPDIR/claude"
  export TEAM_OS_NOW="$NOW_EPOCH"
  AUDIT="$CLAUDE_HOME/team-os/audit.jsonl"
  mkdir -p "$CLAUDE_HOME/team-os"
}

line() { # ts rule repo(json)
  printf '{"ts":"%s","rule":"%s","tool":"Bash","repo":%s,"version":"abc1234"}\n' "$1" "$2" "${3:-\"team-os\"}"
}

@test "a missing audit file says nothing is recorded" {
  run --separate-stderr "$STATS"
  [ "$status" -eq 0 ]
  [ "$output" = "No guard blocks recorded yet" ]
}

@test "an empty audit file says nothing is recorded" {
  : > "$AUDIT"
  run --separate-stderr "$STATS"
  [ "$status" -eq 0 ]
  [ "$output" = "No guard blocks recorded yet" ]
}

@test "counts per rule are correct, most blocks first" {
  {
    line 2026-11-10T09:00:00Z no-force-push
    line 2026-11-10T10:00:00Z no-env-read
    line 2026-11-10T11:00:00Z no-force-push
    line 2026-11-10T12:00:00Z no-force-push
  } > "$AUDIT"
  run --separate-stderr "$STATS"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"Guard blocks in the last 8 weeks"* ]]
  rules="$(printf '%s\n' "$output" | sed -n '/^By rule:/,/^By week:/p' | sed '1d;$d')"
  [ "$(printf '%s\n' "$rules" | sed -n 1p | awk '{print $1, $2}')" = "3 no-force-push" ]
  [ "$(printf '%s\n' "$rules" | sed -n 2p | awk '{print $1, $2}')" = "1 no-env-read" ]
}

@test "malformed lines are skipped without error" {
  {
    line 2026-11-10T09:00:00Z no-force-push
    printf 'garbage text\n\n5\n"str"\n'
    printf '{"ts":"not-a-date","rule":"x","repo":null}\n'
    printf '{"rule":"x","repo":null}\n'
  } > "$AUDIT"
  run --separate-stderr "$STATS"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" != *"jq: error"* ]]
  [[ "$output" == *"1 no-force-push"* ]]
  [[ "$output" != *" x"* ]]
}

@test "lines older than N weeks are excluded and a custom N narrows the window" {
  {
    line 2026-11-10T09:00:00Z recent-rule
    line 2026-11-01T09:00:00Z mid-rule
    line 2026-08-01T09:00:00Z old-rule
  } > "$AUDIT"
  run --separate-stderr "$STATS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recent-rule"* ]]
  [[ "$output" == *"mid-rule"* ]]
  [[ "$output" != *"old-rule"* ]]
  run --separate-stderr "$STATS" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Guard blocks in the last 1 weeks"* ]]
  [[ "$output" == *"recent-rule"* ]]
  [[ "$output" != *"mid-rule"* ]]
}

@test "ISO week labels follow the ISO year across a year boundary" {
  TEAM_OS_NOW="$(date -u -d 2026-01-05T12:00:00Z +%s)" # fixed date, not the real clock
  export TEAM_OS_NOW
  line 2025-12-29T09:00:00Z no-force-push > "$AUDIT"
  run --separate-stderr "$STATS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 2026-W01"* ]]
}

@test "a null repo shows as (none)" {
  line 2026-11-10T09:00:00Z no-force-push null > "$AUDIT"
  run --separate-stderr "$STATS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 (none)"* ]]
}

@test "only lines outside the window say there are no blocks in the window" {
  line 2026-01-01T09:00:00Z no-force-push > "$AUDIT"
  run --separate-stderr "$STATS" 2
  [ "$status" -eq 0 ]
  [ "$output" = "No guard blocks in the last 2 weeks" ]
}

@test "stats.sh does not change the audit file" {
  line 2026-11-10T09:00:00Z no-force-push > "$AUDIT"
  before="$(cksum < "$AUDIT")"
  run --separate-stderr "$STATS"
  [ "$(cksum < "$AUDIT")" = "$before" ]
}
