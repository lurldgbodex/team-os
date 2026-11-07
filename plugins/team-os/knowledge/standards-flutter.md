# Flutter standards

Adds to `standards.md`; does not repeat or override it. Starter rules for the POC; the Flutter owners replace them via pull request.

Applies when the repo has a `pubspec.yaml` with a `flutter` dependency.

## Formatting and linting

- Run `dart format` before committing.
- `flutter analyze` must pass with no new warnings.
- Keep an `analysis_options.yaml` that includes `flutter_lints` or a stricter set. Do not disable a rule without a comment saying why.

## Layout

- Organise `lib/` feature-first: `lib/features/<feature>/` with its own UI, state and data code.
- Keep shared code in `lib/core/` or a similar folder. Do not import across features' internals.
- Keep business logic out of `build()`. Put it in a controller, notifier, bloc or the repo's chosen state layer.
- Use `const` constructors and widgets wherever possible.
- Split large widgets into smaller widget classes, not helper methods that return widgets.

## Errors

- Never leave a `Future` unawaited. If it is intentional, wrap it in `unawaited()` and say why.
- Surface failures as explicit UI states (loading, error, empty, data). Do not leave the screen blank or spinning.
- Do not use `BuildContext` after an `await` without checking `mounted` (or `context.mounted` outside a `State`).

## Testing

- Cover UI with widget tests. Use `pumpAndSettle` sparingly and prefer explicit `pump` durations.
- Add golden tests only for stable, self-contained widgets. Pin the font and device size.
- Mock platform channels with `TestDefaultBinaryMessengerBinding`.

## Dependencies

- Use caret constraints (`^x.y.z`) in `pubspec.yaml`, never `any`. The committed lockfile gives reproducible builds.
- Commit `pubspec.lock` for apps. Do not commit it for packages.
- Run `flutter pub upgrade` deliberately, in its own pull request.
