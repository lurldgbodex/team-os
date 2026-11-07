# Team knowledge index

Read this file first. Open only the documents that match the question.

| Document | Read it when |
|---|---|
| `standards.md` | Writing or reviewing code, naming things, writing tests, committing, opening PRs |
| `standards-go.md` | Writing or reviewing Go code (repo has `go.mod`). Read with `standards.md` |
| `standards-flutter.md` | Writing or reviewing Flutter code (repo has `pubspec.yaml` with a `flutter` dependency). Read with `standards.md` |
| `standards-java.md` | Writing or reviewing Java code (repo has `pom.xml` or `build.gradle(.kts)` with `src/main/java`). Read with `standards.md` |
| `standards-typescript.md` | Writing or reviewing TypeScript code (repo has `tsconfig.json` or `typescript` in `package.json`). Read with `standards.md` |
| `example-service.md` | You need a model of what a project knowledge page should contain (replace with your real projects) |
| `team-os.md` | Questions about how Team OS itself works: agents, hooks, rules, updates |

## How to add knowledge

1. Create one markdown file per project or topic in this folder.
2. Add one row to the table above saying **when** to read it.
3. Open a pull request. Merging to the main branch delivers it to everyone on their next `git pull`.

Keep facts short and checkable. Say who owns each fact and when it was last verified.
