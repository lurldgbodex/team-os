#!/usr/bin/env bats

load test_helper

setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "install runs end to end in a clean home" {
  run "$WORK_REPO/install.sh" --yes
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_HOME/team-os/config.env" ]
  [ -d "$CLAUDE_HOME/team-os/personal/.git" ]
  [ -x "$WORK_REPO/.git/hooks/post-merge" ]
  run jq -r '.statusLine.command' "$CLAUDE_HOME/settings.json"
  [[ "$output" == *"statusline.sh" ]]
  run jq -r '.permissions.deny | length' "$CLAUDE_HOME/settings.json"
  [ "$output" -ge 1 ]
}

@test "install twice is safe and changes nothing" {
  "$WORK_REPO/install.sh" --yes >/dev/null
  jq -S . "$CLAUDE_HOME/settings.json" > "$SANDBOX/first.json"
  echo "keep me" > "$CLAUDE_HOME/team-os/personal/note.md"
  run "$WORK_REPO/install.sh" --yes
  [ "$status" -eq 0 ]
  jq -S . "$CLAUDE_HOME/settings.json" > "$SANDBOX/second.json"
  run diff "$SANDBOX/first.json" "$SANDBOX/second.json"
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_HOME/team-os/personal/note.md" ]
}

@test "install keeps an existing status line when asked" {
  echo '{"statusLine":{"type":"command","command":"/usr/local/bin/mine.sh"}}' > "$CLAUDE_HOME/settings.json"
  "$WORK_REPO/install.sh" --yes >/dev/null
  run jq -r '.statusLine.command' "$CLAUDE_HOME/settings.json"
  [ "$output" = "/usr/local/bin/mine.sh" ]
}

@test "uninstall restores settings and keeps personal notes" {
  echo '{"model":"opus","statusLine":{"type":"command","command":"/usr/local/bin/mine.sh"}}' > "$CLAUDE_HOME/settings.json"
  jq -S . "$CLAUDE_HOME/settings.json" > "$SANDBOX/before.json"
  "$WORK_REPO/install.sh" --yes --status-line team >/dev/null
  echo "keep me" > "$CLAUDE_HOME/team-os/personal/note.md"

  run "$WORK_REPO/uninstall.sh"
  [ "$status" -eq 0 ]

  jq -S . "$CLAUDE_HOME/settings.json" > "$SANDBOX/after.json"
  run diff "$SANDBOX/before.json" "$SANDBOX/after.json"
  [ "$status" -eq 0 ]
  [ ! -e "$WORK_REPO/.git/hooks/post-merge" ]
  [ ! -e "$CLAUDE_HOME/team-os/config.env" ]
  [ -f "$CLAUDE_HOME/team-os/personal/note.md" ]
}

@test "git pull refreshes rules through the post-merge hook" {
  bare="$SANDBOX/remote.git"
  git init -q --bare -b main "$bare"
  git -C "$WORK_REPO" remote add origin "$bare"
  git -C "$WORK_REPO" push -q origin HEAD:main
  git -C "$WORK_REPO" branch -u origin/main >/dev/null
  "$WORK_REPO/install.sh" --yes >/dev/null

  other="$SANDBOX/other"
  git clone -q "$bare" "$other"
  cat > "$other/plugins/team-os/policy/rules/deny-new-thing.json" <<'EOF'
{"id":"deny-new-thing","type":"deny","rule":"Bash(rm -rf /:*)","why":"never","owner":"platform"}
EOF
  git -C "$other" add -A
  git -C "$other" -c user.email=t@t -c user.name=t commit -qm "feat: new rule"
  git -C "$other" push -q origin HEAD:main

  run jq -r '.permissions.deny | index("Bash(rm -rf /:*)")' "$CLAUDE_HOME/settings.json"
  [ "$output" = "null" ]

  git -C "$WORK_REPO" pull -q --ff-only
  run jq -r '.permissions.deny | index("Bash(rm -rf /:*)")' "$CLAUDE_HOME/settings.json"
  [ "$output" != "null" ]
}

@test "install --enforced also writes the managed file" {
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  run "$WORK_REPO/install.sh" --yes --enforced
  [ "$status" -eq 0 ]
  [ -f "$TEAM_OS_MANAGED_DIR/managed-settings.d/50-team-os.json" ]
  [ -f "$CLAUDE_HOME/team-os/config.env" ]
  run jq -r '.permissions.deny | length' "$CLAUDE_HOME/settings.json"
  [ "$output" -ge 1 ]
}

@test "uninstall removes the managed file and keeps other drop-ins" {
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  mkdir -p "$TEAM_OS_MANAGED_DIR/managed-settings.d"
  echo '{}' > "$TEAM_OS_MANAGED_DIR/managed-settings.d/10-it.json"
  "$WORK_REPO/install.sh" --yes --enforced >/dev/null
  run "$WORK_REPO/uninstall.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$TEAM_OS_MANAGED_DIR/managed-settings.d/50-team-os.json" ]
  [ -f "$TEAM_OS_MANAGED_DIR/managed-settings.d/10-it.json" ]
}

@test "refresh rewrites a stale enforced file" {
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  "$WORK_REPO/install.sh" --yes --enforced >/dev/null
  echo '{"id":"deny-new-thing","type":"deny","rule":"Bash(frobnicate:*)","why":"never","owner":"platform"}' \
    > "$WORK_REPO/plugins/team-os/policy/rules/deny-new-thing.json"
  run "$WORK_REPO/bin/refresh.sh"
  [ "$status" -eq 0 ]
  run jq -r '.permissions.deny | index("Bash(frobnicate:*)")' "$TEAM_OS_MANAGED_DIR/managed-settings.d/50-team-os.json"
  [ "$output" != "null" ]
}

@test "install --enforced keeps going and exits non-zero when the managed dir is read-only" {
  [ "$(id -u)" -eq 0 ] && skip "root can write anywhere"
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  mkdir -p "$TEAM_OS_MANAGED_DIR/managed-settings.d"
  chmod 555 "$TEAM_OS_MANAGED_DIR/managed-settings.d"
  run "$WORK_REPO/install.sh" --yes --enforced
  chmod 755 "$TEAM_OS_MANAGED_DIR/managed-settings.d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sudo"* ]]
  [ ! -e "$TEAM_OS_MANAGED_DIR/managed-settings.d/50-team-os.json" ]
  run jq -r '.statusLine.command' "$CLAUDE_HOME/settings.json"
  [[ "$output" == *"statusline.sh" ]]
  run jq -r '.permissions.deny | length' "$CLAUDE_HOME/settings.json"
  [ "$output" -ge 1 ]
}

@test "install --enforced twice leaves the managed file byte-identical" {
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  "$WORK_REPO/install.sh" --yes --enforced >/dev/null
  cp "$TEAM_OS_MANAGED_DIR/managed-settings.d/50-team-os.json" "$SANDBOX/first.json"
  run "$WORK_REPO/install.sh" --yes --enforced
  [ "$status" -eq 0 ]
  cmp "$SANDBOX/first.json" "$TEAM_OS_MANAGED_DIR/managed-settings.d/50-team-os.json"
}

@test "refresh tells you to run sudo when the enforced file is stale and the dir is read-only" {
  [ "$(id -u)" -eq 0 ] && skip "root can write anywhere"
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  f="$TEAM_OS_MANAGED_DIR/managed-settings.d/50-team-os.json"
  "$WORK_REPO/install.sh" --yes --enforced >/dev/null
  cp "$f" "$SANDBOX/before.json"
  echo '{"id":"deny-new-thing","type":"deny","rule":"Bash(frobnicate:*)","why":"never","owner":"platform"}' \
    > "$WORK_REPO/plugins/team-os/policy/rules/deny-new-thing.json"
  chmod 555 "$TEAM_OS_MANAGED_DIR/managed-settings.d"
  run "$WORK_REPO/bin/refresh.sh"
  chmod 755 "$TEAM_OS_MANAGED_DIR/managed-settings.d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"out of date"* ]]
  [[ "$output" == *"sudo"* ]]
  cmp "$SANDBOX/before.json" "$f"
}

@test "uninstall warns and exits 0 when the enforced file is in a read-only dir" {
  [ "$(id -u)" -eq 0 ] && skip "root can write anywhere"
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  f="$TEAM_OS_MANAGED_DIR/managed-settings.d/50-team-os.json"
  "$WORK_REPO/install.sh" --yes --enforced >/dev/null
  chmod 555 "$TEAM_OS_MANAGED_DIR/managed-settings.d"
  run "$WORK_REPO/uninstall.sh"
  chmod 755 "$TEAM_OS_MANAGED_DIR/managed-settings.d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sudo"* ]]
  [ -f "$f" ]
}
