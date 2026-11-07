# Go standards

Adds to `standards.md`; does not repeat or override it. Starter rules for the POC; the Go owners replace them via pull request.

Applies when the repo has `go.mod`.

## Formatting and linting

- Run `gofmt` (or `goimports`) before committing. Never hand-format.
- `go vet ./...` must pass.
- Run `golangci-lint` when the repo configures it. Do not add `//nolint` without a reason in the same comment.

## Layout

- Entry points live in `cmd/<name>/`. Private packages live in `internal/`.
- Name packages by what they provide, in short lowercase. Avoid `util`, `common` and `helpers`.
- Pass `context.Context` as the first parameter. Never store it in a struct.
- Accept interfaces, return concrete types. Define an interface where it is used.

## Errors

- Wrap with context: `fmt.Errorf("load config: %w", err)`.
- Compare with `errors.Is` and `errors.As`, never by string or `==` on wrapped errors.
- No `panic` in library code. Reserve it for unrecoverable startup failures in `main`.
- Error strings are lowercase and have no trailing punctuation.

## Testing

- Use table-driven tests with `t.Run` subtests. Call `t.Helper()` in test helpers.
- Use `t.TempDir()` and `t.Setenv()` instead of touching real paths or the real environment.
- Use `httptest` for HTTP clients and servers. Inject a clock or a fake instead of calling `time.Now` directly.
- CI runs `go test -race ./...`.

## Dependencies

- Run `go mod tidy` and commit `go.mod` and `go.sum` together.
- Prefer the standard library. Add a module only when it saves real work.
- Do not commit `replace` directives, except for a module inside the same repo.
