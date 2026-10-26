# Engineering standards

Starter standards for the POC. Replace with your team's real ones via pull request.

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

- Branches: `<type>/<ticket-id>-<slug>`, for example `feat/PROJ-123-add-rate-cache`.
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
