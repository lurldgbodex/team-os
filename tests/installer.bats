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
