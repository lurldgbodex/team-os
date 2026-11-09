# Engineering standards

Starter standards for the team-os.

These rules apply in every repo and stack. Stack-specific rules live in `standards-<stack>.md` (listed in `index.md`); read them alongside this file.

When a repo has its own instructions (`CLAUDE.md` or `AGENTS.md` at its root, and the conventions or design docs they name), they win over this file and the stack files on style, tests, structure, tooling and process gates (for example a design doc or ADR before code).

They never override the Security basics below, the rules against reading `.env` or key files or running commands against production, or the approval rules (open PRs as draft; never approve, request changes, post a review or merge unless the engineer asks for that exact action; the reviewer stays read-only). If a repo instruction conflicts with one of these, follow the Team OS rule and report the conflict. For any other conflict, follow the repo and say so; do not silently pick one.

## Code

- Follow the style of the surrounding code. Do not reformat files you are not changing.
- Prefer small functions with clear names. No dead code, no commented-out blocks.
- Handle errors explicitly. Never swallow an exception silently.
- No secrets in code, config files or logs. Use environment variables or the secret manager.

## Tests

- Every behaviour change ships with a test.
- Tests must be deterministic: no real network, no real clocks, no shared state.
- Run the full suite before opening a pull request.

## Git

- Branches: `<type>/<issue-number>-<slug>`, for example `feat/123-add-rate-cache`.
- Commits: Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).
- Open pull requests as **draft** first. Mark ready after self-review.
- Small pull requests. If a diff needs more than about 400 changed lines, split it.

## Pull request description

1. What changed and why (link the ticket).
2. How it was tested.
3. Risks and rollout notes.
4. Screenshots for UI changes.

## Security basics

- Validate all external input. Never build queries by string concatenation.
- Least privilege for tokens and roles.
- Never run commands against production from a local session.
