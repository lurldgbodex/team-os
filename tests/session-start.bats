#!/usr/bin/env bats
# Session start: version line plus a nudge when no knowledge page lists the repo.

load test_helper

setup() {
  setup_sandbox
  HOOK="$WORK_REPO/plugins/team-os/hooks/session-start.sh"
  PERSONAL="$HOME/.claude/team-os/personal"
  PROJECT="$SANDBOX/proj"
  make_project "$PROJECT" "https://github.com/o/proj.git"
}

teardown() {
  teardown_sandbox
}

# $1 = dir, $2 = origin URL
make_project() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" remote add origin "$2"
}

run_hook() {
  CLAUDE_PLUGIN_ROOT="$WORK_REPO/plugins/team-os" CLAUDE_PROJECT_DIR="${1:-$PROJECT}" run "$HOOK"
}

write_personal() {
  mkdir -p "$PERSONAL/projects"
  printf '%s\n' "$2" > "$PERSONAL/projects/$1"
}

@test "an inline repos entry in a personal note suppresses the nudge" {
  write_personal x.md $'---\nrepos: [o/proj]\n---\n# X'
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"onboard-repo"* ]]
  [ "${#lines[@]}" -eq 1 ]
}

@test "a block list repos entry suppresses the nudge" {
  write_personal x.md $'---\nrepos:\n  - o/other\n  - "o/proj"\n---\n# X'
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"onboard-repo"* ]]
}

@test "a note in the shared knowledge folder suppresses the nudge" {
  printf '%s\n' '---' 'repos: [o/proj]' '---' '# Shared' > "$WORK_REPO/plugins/team-os/knowledge/proj.md"
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"onboard-repo"* ]]
}

@test "no note prints the suggestion" {
  run_hook
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "Team OS · "* ]]
  [[ "$output" == *"No Team OS knowledge page lists o/proj"* ]]
  [[ "$output" == *"/team-os:onboard-repo"* ]]
}

@test "a near-miss repo name does not match" {
  write_personal x.md $'---\nrepos: [o/proj-v2]\n---\n# X'
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"No Team OS knowledge page lists o/proj."* ]]
}

@test "outside a git repo only the version line is printed" {
  mkdir -p "$SANDBOX/plain"
  run_hook "$SANDBOX/plain"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "Team OS · "* ]]
}

@test "a missing personal folder still exits 0 and nudges" {
  [ ! -d "$PERSONAL" ]
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"/team-os:onboard-repo"* ]]
}

@test "malformed frontmatter still exits 0 and nudges" {
  write_personal unclosed.md $'---\nrepos: [o/other]\n# never closed'
  write_personal garbage.md $'---\n::: [ {{ \nrepos: [[[\n'
  write_personal binaryish.md $'\001\002---\nrepos: o/proj'
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"No Team OS knowledge page lists o/proj"* ]]
}

@test "an unclosed frontmatter does not count as a match" {
  write_personal unclosed.md $'---\nrepos: [o/proj]\n# never closed'
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"onboard-repo"* ]]
}

@test "the Team OS checkout itself gets no nudge" {
  git -C "$WORK_REPO" remote add origin "https://github.com/o/team-os.git"
  run_hook "$WORK_REPO"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "a non-GitHub remote gets no nudge" {
  git -C "$PROJECT" remote set-url origin "https://gitlab.com/o/proj.git"
  run_hook
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "ssh remote forms resolve to owner/repo" {
  write_personal x.md $'---\nrepos: [o/proj]\n---\n'
  git -C "$PROJECT" remote set-url origin "git@github.com:o/proj.git"
  run_hook
  [ "${#lines[@]}" -eq 1 ]
  git -C "$PROJECT" remote set-url origin "ssh://git@github.com/o/proj"
  run_hook
  [ "${#lines[@]}" -eq 1 ]
  git -C "$PROJECT" remote set-url origin "https://github.com/o/proj/"
  run_hook
  [ "${#lines[@]}" -eq 1 ]
}

@test "matching ignores case" {
  write_personal x.md $'---\nrepos: ["O/Proj"]\n---\n'
  git -C "$PROJECT" remote set-url origin "git@github.com:o/PROJ.git"
  run_hook
  [ "${#lines[@]}" -eq 1 ]
}
