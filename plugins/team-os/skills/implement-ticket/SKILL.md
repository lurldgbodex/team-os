---
name: implement-ticket
description: Take a Jira ticket to a draft pull request. Reads the ticket, plans, implements with the coder subagent, runs tests, opens a draft PR and self-reviews. Use when the engineer gives a ticket ID like PROJ-123.
argument-hint: "<TICKET-ID>"
---

# Implement a ticket

Input: a ticket ID (for example `PROJ-123`), passed as the argument.

Follow these steps in order. Stop and ask the engineer if a step cannot be completed.

## 1. Understand the ticket

- Fetch the ticket with the Jira (Atlassian) connector: summary, description, acceptance criteria, linked tickets.
- If no Jira connector is available, ask the engineer to paste the ticket text and continue.
- Ask the `librarian` subagent what the shared knowledge says about the affected project and standards.
- Restate the goal and acceptance criteria in three or four lines.

## 2. Confirm the base and branch

- Run `git status` and confirm the working tree is clean. If not, stop and ask.
- Confirm the base branch with the engineer if it is not obvious (main, production, develop).
- Create a branch named `<type>/<ticket-id>-<short-slug>`, for example `feat/PROJ-123-add-fx-rate-cache`.

## 3. Plan

Write a short plan: files to change, tests to add, risks. Show it to the engineer and wait for approval before coding.

## 4. Implement

- Delegate each well-scoped step to the `coder` subagent, giving it the plan step and the relevant standards.
- Run the project's tests after each step. Fix failures before moving on.
- Commit with Conventional Commits, referencing the ticket ID.

## 5. Verify

- Run the full test suite and linter. Report exact results.
- If something cannot be run, say so. Do not claim it passed.

## 6. Draft pull request

- Push the branch and open a **draft** PR with `gh pr create --draft`.
- Title: `<type>(<scope>): <summary> (<TICKET-ID>)`.
- Body: what and why, how it was tested, link to the ticket, screenshots if UI changed.

## 7. Self-review

Review your own diff as a reviewer would and list findings as a short checklist:

- Scope: only what the ticket needs?
- Tests: every behaviour change covered?
- Security: secrets, input validation, auth?
- Standards: matches `standards.md`?

Fix what you find, then tell the engineer the PR link, the test results, and anything left for them to decide.
