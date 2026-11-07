---
name: create-ticket
description: Turn a rough description into a well-formed GitHub issue (problem, acceptance criteria, scope, test notes), show it for approval, then create it. Use when the engineer describes work to be done and wants a ticket for it.
argument-hint: "<what you want done, in your own words>"
---

# Create a ticket (GitHub issue)

Input: a plain description of the work, passed as the argument or written in the chat.
The ticket system is **GitHub Issues** in the repository you are standing in.

## 1. Find the repository

- Run `git remote get-url origin` and work out `owner/repo`. If this is not a git repository, ask which `owner/repo` the issue belongs to.
- Check the issue does not already exist: search open issues with the GitHub connector (`search_issues`), or `gh issue list --search "<keywords>" --state open`. If something close exists, show it and ask whether to use it instead.

## 2. Ground it in the code

- Ask the `librarian` subagent what the shared knowledge says about this project and its standards.
- Look at the code the work touches (read-only) so the ticket names real files, modules or endpoints. Do not guess names.
- If the description is ambiguous in a way that changes the scope, ask **one** short question. Otherwise carry on.

## 3. Draft the issue

Use this shape and keep it short:

```
Title: <type>: <imperative summary>        (type = feat, fix, chore, docs, refactor)

## Problem
Why this is needed, in two or three sentences.

## Proposed change
What will be different when this is done. Name the likely files or modules.

## Acceptance criteria
- [ ] Observable, testable outcomes (one per line)

## Out of scope
What this ticket deliberately does not do.

## Test notes
How to verify it, and which tests to add.
```

Suggest labels from the ones that already exist in the repo (`gh label list`); never invent new labels without asking. If the work is larger than one pull request, say so and propose splitting it into smaller tickets.

## 4. Approve, then create

- Show the full draft and wait for the engineer to approve or edit it. **Do not create anything before approval.**
- Create it with the GitHub connector (`issue_write`, method `create`). If the connector is unavailable, use `gh issue create --title ... --body-file ...` with the body written to a temporary file.
- Report the issue number and URL, and offer the next step: `/team-os:implement-ticket <number>`.
