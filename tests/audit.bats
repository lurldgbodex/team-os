#!/usr/bin/env bats
# The guard writes one line per block to a local audit file.

load test_helper

GUARD="$REPO_ROOT/plugins/team-os/hooks/guard.sh"

setup() {
  AUDIT="$BATS_TEST_TMPDIR/claude/team-os/audit.jsonl"
  FORCE_CMD="git push --force origin secret-branch-xyz"
}

teardown() {
  chmod -R u+w "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

@test "a denied call writes one valid audit line" {
  run guard_bash "$FORCE_CMD"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$AUDIT")" -eq 1 ]
  jq -e '.rule == "no-force-push" and .tool == "Bash"
    and has("ts") and has("rule") and has("tool") and has("repo") and has("version")' "$AUDIT"
}

@test "the audit line holds no command text or file path" {
  guard_bash "$FORCE_CMD" >/dev/null
  guard_read "/work/app/id_rsa" >/dev/null
  [ "$(wc -l < "$AUDIT")" -eq 2 ]
  ! grep -q "secret-branch-xyz" "$AUDIT"
  ! grep -q "id_rsa" "$AUDIT"
  ! grep -q "/work/app" "$AUDIT"
}

@test "an allowed call writes nothing" {
  run guard_bash "git status"
  [ "$status" -eq 0 ]
  [ ! -e "$AUDIT" ]
}

@test "a read-only audit directory does not change the deny output" {
  if [ "$(id -u)" -eq 0 ]; then skip "root ignores file permissions"; fi
  mkdir -p "$BATS_TEST_TMPDIR/claude/team-os"
  chmod 500 "$BATS_TEST_TMPDIR/claude/team-os"
  run guard_bash "$FORCE_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *'permissionDecision": "deny"'* ]]
}

@test "an unusable CLAUDE_HOME still denies" {
  : > "$BATS_TEST_TMPDIR/notadir"
  run bash -c 'jq -n --arg c "$1" "{tool_name:\"Bash\", tool_input:{command:\$c}}" | CLAUDE_HOME="$2" "$3"' \
    _ "$FORCE_CMD" "$BATS_TEST_TMPDIR/notadir/claude" "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *'permissionDecision": "deny"'* ]]
}

@test "two denies append two lines" {
  guard_bash "$FORCE_CMD" >/dev/null
  guard_bash "$FORCE_CMD" >/dev/null
  [ "$(wc -l < "$AUDIT")" -eq 2 ]
}

@test "repo is the basename of the git repo in cwd" {
  mkdir "$BATS_TEST_TMPDIR/myrepo"
  git -C "$BATS_TEST_TMPDIR/myrepo" init -q
  jq -n --arg c "$FORCE_CMD" --arg d "$BATS_TEST_TMPDIR/myrepo" \
    '{tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' \
    | CLAUDE_HOME="$BATS_TEST_TMPDIR/claude" "$GUARD" >/dev/null
  [ "$(jq -r '.repo' "$AUDIT")" = "myrepo" ]
}
