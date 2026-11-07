---
name: review-pr
description: Review a GitHub pull request against its linked issue and the team standards, report findings by severity, and optionally post them as a review. Use when the engineer gives a PR number or asks for a code review of the current branch.
argument-hint: "[PR-number]"
---

# Review a pull request

Input: a PR number. With no argument, review the PR for the current branch (`gh pr view --json number,url`). If there is none, review the diff of the current branch against its base and say so.

This skill is **read-only until the engineer approves posting**. It never approves, requests changes on, merges or pushes anything.

## 1. Gather

- Read the PR: title, description, base and head branches, changed files, CI status (`gh pr view <n> --json ...`, `gh pr checks <n>`, or the GitHub connector's `pull_request_read`).
- Read the linked issue (look for `Closes #n`) and note its acceptance criteria. If there is no linked issue, say so and review against the PR description.
- Get the diff (`gh pr diff <n>`). For a large PR, review file by file.

## 2. Review

Delegate the reading to the `reviewer` subagent, giving it the diff, the acceptance criteria and a pointer to `${CLAUDE_PLUGIN_ROOT}/knowledge/standards.md`. It checks, in this order:

1. **Does it do what the issue asks?** Each acceptance criterion: met, partly met or missing.
2. **Correctness**: logic errors, edge cases, error handling, concurrency, off-by-one and null cases.
3. **Security**: secrets, input validation, auth, injection, unsafe deserialisation, logging of sensitive data.
4. **Tests**: every behaviour change covered, tests that would actually fail if the code were wrong.
5. **Scope and standards**: only what the issue needs, naming, structure, Conventional Commits, no stray files.

## 3. Report

Show the findings in the conversation, most serious first. Each finding gets: severity (**blocker**, **should fix**, **nit**), `file:line`, what is wrong, and a concrete suggestion. Only report issues you are confident about, and say what you could not check (for example tests you could not run). End with a verdict line: *ready*, *ready after fixes* or *not ready*, with one sentence of reasoning.

## 4. Post (only if asked)

- Ask the engineer whether to post the findings to the PR. If yes, create a pending review, add one line comment per finding, then submit it with the `COMMENT` event (GitHub connector: `pull_request_review_write` then `add_comment_to_pending_review`; fallback: `gh pr review <n> --comment --body-file ...`).
- Never submit `APPROVE` or `REQUEST_CHANGES` unless the engineer explicitly asks for that exact action.
- If the engineer asks you to fix the findings, switch to the PR branch and delegate to the `coder` subagent, one finding per commit.
