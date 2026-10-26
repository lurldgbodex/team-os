# Shared setup for the bats tests.
# Every test runs against a throwaway HOME so it never touches real settings.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX/home"
  export CLAUDE_HOME="$HOME/.claude"
  export TEAM_OS_SKIP_CLAUDE=1
  mkdir -p "$CLAUDE_HOME"

  # Work on a private copy of the repo so hook/config changes stay contained.
  WORK_REPO="$SANDBOX/repo"
  cp -R "$REPO_ROOT" "$WORK_REPO"
  rm -rf "$WORK_REPO/.git"
  git -C "$WORK_REPO" init -q
  git -C "$WORK_REPO" -c user.email=t@t -c user.name=t add -A >/dev/null
  git -C "$WORK_REPO" -c user.email=t@t -c user.name=t commit -qm "test" >/dev/null
}

teardown_sandbox() {
  rm -rf "$SANDBOX"
}

# Run guard.sh with a Bash command and print its stdout.
guard_bash() {
  jq -n --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}' | "$REPO_ROOT/plugins/team-os/hooks/guard.sh"
}

guard_read() {
  jq -n --arg p "$1" '{tool_name:"Read", tool_input:{file_path:$p}}' | "$REPO_ROOT/plugins/team-os/hooks/guard.sh"
}
