#!/usr/bin/env bats

load test_helper

setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

statusline() {
  printf '%s' "$1" | "$REPO_ROOT/plugins/team-os/hooks/statusline.sh"
}

@test "status line shows model, context and version" {
  run statusline '{"model":{"display_name":"Sonnet 5.5"},"context_window":{"used_percentage":34}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sonnet 5.5"* ]]
  [[ "$output" == *"ctx"* ]]
  [[ "$output" == *"34%"* ]]
  [[ "$output" == *"Team OS"* ]]
}

@test "status line turns yellow from 70 and red from 90" {
  run statusline '{"model":{"display_name":"X"},"context_window":{"used_percentage":75}}'
  [[ "$output" == *$'\033[33m'* ]]
  run statusline '{"model":{"display_name":"X"},"context_window":{"used_percentage":95}}'
  [[ "$output" == *$'\033[31m'* ]]
}

@test "status line shows usage only when the fields exist" {
  run statusline '{"model":{"display_name":"X"},"context_window":{"used_percentage":10}}'
  [[ "$output" != *"5h"* ]]
  run statusline '{"model":{"display_name":"X"},"context_window":{"used_percentage":10},"rate_limits":{"five_hour":{"used_percentage":28},"seven_day":{"used_percentage":82}}}'
  [[ "$output" == *"5h"* ]]
  [[ "$output" == *"7d"* ]]
}

@test "session start prints the version" {
  CLAUDE_PLUGIN_ROOT="$WORK_REPO/plugins/team-os" run "$WORK_REPO/plugins/team-os/hooks/session-start.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == "Team OS · "* ]]
}

@test "session start warns when the checkout is behind upstream" {
  bare="$SANDBOX/remote.git"
  git init -q --bare -b main "$bare"
  git -C "$WORK_REPO" remote add origin "$bare"
  git -C "$WORK_REPO" push -q origin HEAD:main 2>/dev/null
  git -C "$WORK_REPO" branch -q --set-upstream-to=origin/main 2>/dev/null || git -C "$WORK_REPO" branch -u origin/main >/dev/null

  other="$SANDBOX/other"
  git clone -q "$bare" "$other"
  git -C "$other" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "new rule"
  git -C "$other" push -q origin HEAD:main
  git -C "$WORK_REPO" fetch -q

  CLAUDE_PLUGIN_ROOT="$WORK_REPO/plugins/team-os" run "$WORK_REPO/plugins/team-os/hooks/session-start.sh"
  [[ "$output" == *"behind"* ]]
}
