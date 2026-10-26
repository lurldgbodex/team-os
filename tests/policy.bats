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
