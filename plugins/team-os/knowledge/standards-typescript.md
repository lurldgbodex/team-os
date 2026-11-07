# TypeScript standards

Adds to `standards.md`; does not repeat or override it. Starter rules for the POC; the TypeScript owners replace them via pull request.

Applies when the repo has `tsconfig.json`, or `typescript` in `package.json`.

## Formatting and linting

- Keep `strict: true` in `tsconfig.json`. Do not loosen it to fix an error.
- No `any` without a comment explaining why. Prefer `unknown` and narrow it.
- Run ESLint and Prettier as the repo configures them. Do not add a second formatter.
- Avoid `@ts-ignore`. Use `@ts-expect-error` with a reason when unavoidable.

## Layout

- Use named exports. Use default exports only when the framework requires them.
- Use `import type` for type-only imports.
- Keep types next to the code that owns them. Share them through an explicit module, not a catch-all `types.ts`.

## Errors

- Throw `Error` or a subclass, never a string or plain object.
- In `catch`, treat the value as `unknown` and narrow it before use.
- Validate external data (HTTP, files, env, storage) at the boundary with a schema such as zod, then trust the inferred types inside.
- Handle every Promise: `await` it, return it or attach a handler. No floating promises.

## Testing

- Use the repo's runner (Vitest or Jest). Do not add a second one.
- Use fake timers instead of real waits or sleeps.
- Mock `fetch` or the HTTP client at the boundary. Do not hit real endpoints.
- Test types that matter (for example public API shapes) with the compiler, not casts.

## Dependencies

- Commit the lockfile. Use one package manager per repo.
- Do not add a dependency for a trivial helper. Write it, or use the platform.
- Put tooling in `devDependencies`, not `dependencies`.
