#!/usr/bin/env bats

load test_helper

setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

apply()  { "$WORK_REPO/bin/apply-policy.sh" "$@"; }

@test "apply creates settings and adds deny and ask rules" {
  run apply
  [ "$status" -eq 0 ]
  run jq -r '.permissions.deny | index("Bash(cdk deploy:*)")' "$CLAUDE_HOME/settings.json"
  [ "$output" != "null" ]
  run jq -r '.permissions.ask | index("Bash(git reset --hard:*)")' "$CLAUDE_HOME/settings.json"
  [ "$output" != "null" ]
}

@test "apply adds the gh pr merge ask rule" {
  run apply
  [ "$status" -eq 0 ]
  run jq -r '.permissions.ask | index("Bash(gh pr merge:*)")' "$CLAUDE_HOME/settings.json"
  [ "$output" != "null" ]
}

@test "apply keeps settings the engineer already had" {
  echo '{"model":"opus","permissions":{"allow":["Bash(npm test:*)"],"deny":["Read(secrets/**)"]}}' > "$CLAUDE_HOME/settings.json"
  apply
  run jq -r '.model' "$CLAUDE_HOME/settings.json"
  [ "$output" = "opus" ]
  run jq -r '.permissions.allow[0]' "$CLAUDE_HOME/settings.json"
  [ "$output" = "Bash(npm test:*)" ]
  run jq -r '.permissions.deny | index("Read(secrets/**)")' "$CLAUDE_HOME/settings.json"
  [ "$output" != "null" ]
}

@test "apply twice changes nothing" {
  apply
  cp "$CLAUDE_HOME/settings.json" "$SANDBOX/first.json"
  cp "$CLAUDE_HOME/CLAUDE.md" "$SANDBOX/first.md"
  apply
  run diff "$SANDBOX/first.json" "$CLAUDE_HOME/settings.json"
  [ "$status" -eq 0 ]
  run diff "$SANDBOX/first.md" "$CLAUDE_HOME/CLAUDE.md"
  [ "$status" -eq 0 ]
}

@test "re-apply drops a rule whose file was deleted and keeps the engineer's own" {
  echo '{"permissions":{"deny":["Read(secrets/**)"]}}' > "$CLAUDE_HOME/settings.json"
  apply
  run jq -r '.permissions.deny | index("Bash(cdk deploy:*)")' "$CLAUDE_HOME/settings.json"
  [ "$output" != "null" ]

  rm "$WORK_REPO/plugins/team-os/policy/rules/deny-cdk-deploy.json"
  apply

  run jq -r '.permissions.deny | index("Bash(cdk deploy:*)")' "$CLAUDE_HOME/settings.json"
  [ "$output" = "null" ]
  run jq -r '.permissions.deny | index("Read(secrets/**)")' "$CLAUDE_HOME/settings.json"
  [ "$output" != "null" ]
  run jq -r '.deny | index("Bash(cdk deploy:*)")' "$CLAUDE_HOME/team-os/managed-rules.json"
  [ "$output" = "null" ]
}

@test "remove restores the original settings exactly" {
  echo '{"model":"opus","permissions":{"deny":["Read(secrets/**)"]}}' > "$CLAUDE_HOME/settings.json"
  jq -S . "$CLAUDE_HOME/settings.json" > "$SANDBOX/before.json"
  apply
  apply --remove
  jq -S . "$CLAUDE_HOME/settings.json" > "$SANDBOX/after.json"
  run diff "$SANDBOX/before.json" "$SANDBOX/after.json"
  [ "$status" -eq 0 ]
}

@test "remove leaves an engineer's own CLAUDE.md content alone" {
  printf '# My notes\nAlways use tabs.\n' > "$CLAUDE_HOME/CLAUDE.md"
  apply
  grep -q "team-os:begin" "$CLAUDE_HOME/CLAUDE.md"
  apply --remove
  run cat "$CLAUDE_HOME/CLAUDE.md"
  [[ "$output" == *"Always use tabs."* ]]
  [[ "$output" != *"team-os"* ]]
}

@test "a rule the engineer already had is not removed on uninstall" {
  echo '{"permissions":{"deny":["Bash(cdk deploy:*)"]}}' > "$CLAUDE_HOME/settings.json"
  apply
  apply --remove
  run jq -r '.permissions.deny[0]' "$CLAUDE_HOME/settings.json"
  [ "$output" = "Bash(cdk deploy:*)" ]
}

@test "apply refuses to touch invalid settings JSON" {
  echo '{ not json' > "$CLAUDE_HOME/settings.json"
  run apply
  [ "$status" -ne 0 ]
  run cat "$CLAUDE_HOME/settings.json"
  [ "$output" = "{ not json" ]
}

@test "every rule file has id, type, rule, why and owner" {
  for f in "$REPO_ROOT"/plugins/team-os/policy/rules/*.json; do
    run jq -e '.id and .type and .rule and .why and .owner and (.type == "deny" or .type == "ask")' "$f"
    [ "$status" -eq 0 ]
  done
}

# --- enforced mode ---------------------------------------------------------
managed_file() { echo "$TEAM_OS_MANAGED_DIR/managed-settings.d/50-team-os.json"; }

@test "default apply creates nothing in the managed dir" {
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  apply
  [ ! -e "$TEAM_OS_MANAGED_DIR" ]
}

@test "enforced writes the managed file and leaves user settings alone" {
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  echo '{"model":"opus"}' > "$CLAUDE_HOME/settings.json"
  cp "$CLAUDE_HOME/settings.json" "$SANDBOX/before.json"
  run apply --enforced
  [ "$status" -eq 0 ]
  f="$(managed_file)"
  run jq -r '.permissions.deny | index("Bash(cdk deploy:*)")' "$f"
  [ "$output" != "null" ]
  run jq -r '.permissions.ask | index("Bash(gh pr merge:*)")' "$f"
  [ "$output" != "null" ]
  run jq -r '.extraKnownMarketplaces.teamdata.source | "\(.source) \(.path)"' "$f"
  [ "$output" = "directory $WORK_REPO" ]
  run jq -r '.enabledPlugins["team-os@teamdata"]' "$f"
  [ "$output" = "true" ]
  run ls -l "$f"
  [[ "$output" == "-rw-r--r--"* ]]
  cmp "$SANDBOX/before.json" "$CLAUDE_HOME/settings.json"
  [ ! -e "$CLAUDE_HOME/CLAUDE.md" ]
  [ ! -e "$CLAUDE_HOME/team-os" ]
}

@test "enforced twice leaves the file byte-identical" {
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  apply --enforced
  cp "$(managed_file)" "$SANDBOX/first.json"
  apply --enforced
  cmp "$SANDBOX/first.json" "$(managed_file)"
}

@test "enforced remove deletes only our file" {
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  mkdir -p "$TEAM_OS_MANAGED_DIR/managed-settings.d"
  echo '{}' > "$TEAM_OS_MANAGED_DIR/managed-settings.d/10-it.json"
  apply --enforced
  run apply --enforced --remove
  [ "$status" -eq 0 ]
  [ ! -e "$(managed_file)" ]
  [ -f "$TEAM_OS_MANAGED_DIR/managed-settings.d/10-it.json" ]
  run apply --enforced --remove
  [ "$status" -eq 0 ]
}

@test "enforced without write access explains sudo and leaves nothing behind" {
  [ "$(id -u)" -eq 0 ] && skip "root can write anywhere"
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  d="$TEAM_OS_MANAGED_DIR/managed-settings.d"
  mkdir -p "$d"
  chmod 555 "$d"
  run apply --enforced
  chmod 755 "$d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sudo $WORK_REPO/bin/apply-policy.sh --enforced"* ]]
  [ -z "$(ls -A "$d")" ]
}

@test "enforced check reports a missing, current and stale file" {
  export TEAM_OS_MANAGED_DIR="$SANDBOX/managed"
  run apply --enforced --check
  [ "$status" -eq 1 ]
  apply --enforced
  run apply --enforced --check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  echo '{"id":"deny-x","type":"deny","rule":"Bash(x:*)","why":"w","owner":"o"}' \
    > "$WORK_REPO/plugins/team-os/policy/rules/deny-x.json"
  run apply --enforced --check
  [ "$status" -eq 1 ]
}
