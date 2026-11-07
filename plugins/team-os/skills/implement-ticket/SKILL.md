---
name: implement-ticket
description: Take a GitHub issue to a draft pull request. Reads the issue, plans, implements with the coder subagent, runs tests, opens a draft PR that closes the issue and self-reviews. Use when the engineer gives an issue number like 42 or #42, an issue URL, or pasted ticket text.
argument-hint: "<issue-number | issue-url>"
---

# Implement a ticket (GitHub issue)

Input: an issue number (`42` or `#42`) or URL, passed as the argument. The issue lives in the repository you are standing in, unless a URL points elsewhere.

Follow these steps in order. Stop and ask the engineer if a step cannot be completed.

## 1. Understand the ticket

- Fetch the issue with the GitHub connector (`issue_read`): title, body, labels, comments, linked issues. If the connector is unavailable, use `gh issue view <n> --comments`.
- If there is no issue (the engineer pasted text or described the work), use that text. Offer to run `/team-os:create-ticket` first so the work is tracked, but carry on if they decline.
- Ask the `librarian` subagent what the shared knowledge says about the affected project and standards.
- Restate the goal and acceptance criteria in three or four lines. If the issue has no acceptance criteria, propose some and get them confirmed.

## 2. Confirm the base and branch

- Run `git status` and confirm the working tree is clean. If not, stop and ask.
- Confirm the base branch with the engineer if it is not obvious (main, production, develop).
- Create a branch named `<type>/<issue-number>-<short-slug>`, for example `feat/42-add-fx-rate-cache`.

## 3. Plan

Write a short plan: files to change, tests to add, risks. Show it to the engineer and wait for approval before coding.

## 4. Implement

- Delegate each well-scoped step to the `coder` subagent, giving it the plan step and the relevant standards.
- Run the project's tests after each step. Fix failures before moving on.
- Commit with Conventional Commits, referencing the issue, for example `feat(rates): cache FX rates (#42)`.

## 5. Verify

- Run the full test suite and linter. Report exact results.
- If something cannot be run, say so. Do not claim it passed.

## 6. Draft pull request

- Push the branch and open a **draft** PR (GitHub connector `create_pull_request` with `draft: true`, or `gh pr create --draft`). Use the repository's pull request template if it has one.
- Title: `<type>(<scope>): <summary> (#<issue>)`.
- Body: what and why, how it was tested, screenshots if UI changed, and a line `Closes #<issue>` so merging closes the issue.

## 7. Self-review

Run the `reviewer` subagent on your own diff, or follow `/team-os:review-pr` for the PR you just opened, but **do not post** the review. Fix what it finds as new commits. Then tell the engineer the PR link, the test results, and anything left for them to decide.
