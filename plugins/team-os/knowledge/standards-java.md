# Java standards

Adds to `standards.md`; does not repeat or override it. Starter rules for the POC; the Java owners replace them via pull request.

Applies when the repo root has `pom.xml`, `build.gradle` or `build.gradle.kts`, with `src/main/java`. A Flutter app's `android/` folder does not count.

## Formatting and linting

- Use the formatter the repo configures (for example Spotless with google-java-format). Do not mix styles.
- Run the formatter check as part of the build, for example `./mvnw spotless:check` or `./gradlew spotlessCheck`.
- Fix compiler and static-analysis warnings in code you touch.

## Layout

- Use the standard Maven/Gradle layout: `src/main/java`, `src/test/java`, `src/main/resources`.
- Package by feature, not by layer.
- Use constructor injection. Avoid field injection.
- Use `Optional` for return values only, not for fields or parameters.

## Errors

- Do not catch `Exception` or `Throwable` just to log.
- Do not log and rethrow. Handle the error or let it propagate.
- Use try-with-resources for anything `AutoCloseable`.
- Prefer unchecked domain exceptions at service boundaries. Keep the cause when wrapping.

## Testing

- Use JUnit 5. Use AssertJ assertions when the repo already has it.
- Use Mockito sparingly. Prefer real objects or fakes for simple collaborators.
- Use Testcontainers for databases and brokers.

## Dependencies

- Keep versions in one place: a BOM, `dependencyManagement` or a Gradle version catalog.
- Build with the wrapper (`mvnw` or `gradlew`), never a locally installed tool.
- Do not add a dependency for something the JDK already provides.
