---
name: onboard-repo
description: Read a repository and draft a project knowledge page for it in the example-service.md shape, plus an index.md row. Shows both for approval and writes only to your personal notes. Use when the engineer wants a repo documented for Team OS or says a repo has no knowledge page yet.
argument-hint: "[path to the repo, default current directory]"
---

# Onboard a repo

Input: a path to a repo, passed as the argument. With no argument, use the current directory.

This skill reads the repo and drafts a page. **It writes nothing before the engineer approves**, and it never writes to the shared knowledge folder.

## 1. Find the repo

- Use the `path` argument or the current directory. Run `git -C <path> remote get-url origin` and work out `owner/repo`. Find the default branch (`git -C <path> symbolic-ref --short refs/remotes/origin/HEAD`).
- If this is not a git repository, ask which repo to onboard.

## 2. Check for an existing page

- Read `${CLAUDE_PLUGIN_ROOT}/knowledge/index.md` and list `~/.claude/team-os/personal/projects/` (if it exists).
- If a page for this repo already exists, show it and ask whether to continue before drafting another.

## 3. Read the repo (read-only)

- Read the README, `CLAUDE.md` or `AGENTS.md` and the docs they name.
- Read the build files: `Makefile`, `package.json`, `go.mod`, `pubspec.yaml`, `pom.xml`, `build.gradle(.kts)` and similar.
- Read the CI config (for example `.github/workflows/`) and the top-level folder layout. Also read `CODEOWNERS` if there is one.
- Note which `standards-<stack>.md` applies, using the marker files listed in `index.md`. If none matches, only `standards.md` applies.
- Never open `.env` files or key files.

## 4. Collect the commands

- Record a run, test or lint command only if it exists in the repo as a Makefile target, a package script or a CI step.
- Name the source next to each command, for example `make ci` (Makefile).
- If you find none, say so and mark it unverified. Never invent commands, owners or URLs.

## 5. Draft the page

Use the shape of `${CLAUDE_PLUGIN_ROOT}/knowledge/example-service.md`:

```
# <repo name>

## What it is
## Owners
## Repositories
## Architecture in brief
## Conventions specific to this project
## How to run and test locally
## Known gotchas
## Last verified
```

- Mark anything you could not confirm from the repo as "unverified".
- Leave Owners and on-call blank unless the repo names them (for example in `CODEOWNERS`).
- In Conventions, point to the repo's own `CLAUDE.md` or `AGENTS.md` instead of copying its rules. Copies drift. Say which `standards-<stack>.md` applies.
- In Last verified, write "<today's date>, from <the files you read>".

## 6. Draft the index row

One row for `index.md`:

```
| `<repo>.md` | Read it when <the questions or work this page answers> |
```

## 7. Approve, then write

- Show the full page and the row. Wait for the engineer to approve or edit them. **Do not write anything before approval.**
- On approval, write `~/.claude/team-os/personal/projects/<repo>.md` (create `projects/` if missing). Put the index row at the bottom under a "Proposed index row" heading, so it can be added to the shared index later.
- Never write to the shared knowledge folder.
- If the engineer wants the page shared: use `/team-os:contribute` if that skill exists. Otherwise say it needs a pull request to Team OS (a file in `knowledge/` plus the index row), and stop.

## 8. Report

Name the file you wrote. List everything left "unverified" or blank, so the engineer can fill it in.
