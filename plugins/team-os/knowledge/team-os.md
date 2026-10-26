# How Team OS works

Team OS is a Claude Code plugin distributed from a git repository.

## Pieces

- **Marketplace** (`.claude-plugin/marketplace.json` at the repo root): lets Claude Code install the plugin from the cloned folder.
- **Plugin** (`plugins/team-os/`): agents, skills, hooks, policy and this knowledge bundle.
- **Agents**: `librarian` (reads knowledge, Haiku) and `coder` (implements scoped changes, Sonnet).
- **Skills**: `/team-os:implement-ticket <ID>` (ticket to draft PR) and `/team-os:setup` (post-install check).
- **Hooks**: SessionStart prints the version and warns when behind; PreToolUse blocks dangerous actions.
- **Status line**: model, context %, optional usage, version.
- **Policy**: one small file per rule, merged into the engineer's own Claude settings, reversible.
- **Personal folder**: `~/.claude/team-os/personal/`, private notes, never pushed to the shared repo.

## Updates

`git pull` in the Team OS folder runs a post-merge hook that refreshes the marketplace and plugin, and re-applies policy. New Claude Code sessions use the new version. The version is the git commit.

## Removing it

`./uninstall.sh` reverts everything Team OS changed. The personal notes folder is kept.
