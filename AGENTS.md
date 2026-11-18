# DraftBook Agent Instructions

## Project map

- `Sources/DraftBookCore/`: macOS Swift data model, lifecycle rules, storage and backup.
- `Sources/DraftBook/`: macOS SwiftUI/AppKit UI, text input, Markdown, links, menus and updater.
- `Tests/DraftBookCoreTests/`, `Tests/DraftBookEditorTests/`: macOS/core and editor tests.
- `windows/src/DraftBook.Core/`: Windows C# domain model, schema, persistence and lifecycle.
- `windows/src/DraftBook.Windows/`: Windows WPF UI, system integration and updater.
- `windows/tests/`: Windows core, UI logic and updater smoke tests.
- `windows/spec/`: schema contract, synthetic fixtures, acceptance criteria and current implementation status.
- `docs/`: product, privacy, installation and cross-platform handoff documents.
- `Resources/`, `distribution/`: macOS bundle metadata/assets and release materials.
- `.github/workflows/`: macOS CI and Windows CI/release automation.

Read `docs/AGENT_HANDOFF.md` for cross-platform contracts. For Windows work, also read `docs/WINDOWS_HANDOFF.md` and only the relevant `windows/spec/` documents. Inspect current source and `git status` before relying on recorded version or release state.

## Invariants: do not change without explicit user approval

- macOS bundle identifier and data identity: `com.yangyuxuan.DraftBook`.
- Minimum macOS version: 14.0 (`Package.swift` and `Resources/Info.plist`).
- Current cross-platform JSON schema: v5. Keep field names, enum raw values, defaults and ISO 8601 behavior compatible. Reject newer schemas without overwriting user data.
- Windows package identity: `com.yangyuxuan.DraftBook`; updater channels: `win-x64-beta` and `win-arm64-beta`. Keep them separate from macOS GitHub `v0.9.x` releases.
- Preserve published interfaces: do not rename/remove/change public Swift symbols, serialized fields, Windows package identity, CLI parameters or update asset/channel contracts without explicit approval and a migration plan.
- No dependency additions, version bumps, framework migrations, broad refactors or bulk formatting unless explicitly requested. If a dependency is proposed, explain the need and wait for approval.
- Never use real user drafts, backups, screenshots or credentials in tests, fixtures, logs, issues or commits. Use synthetic fixtures only.
- Never publish, replace or delete a GitHub Release, tag, asset or public download without explicit authorization for that release action.

## Code and error conventions

- Swift: follow the surrounding file's 4-space style; `UpperCamelCase` types and `lowerCamelCase` members; keep platform UI out of `DraftBookCore` where practical.
- C#: follow the existing .NET style: `PascalCase` public types/members, `camelCase` private fields/locals, nullable annotations enabled, warnings treated as errors.
- Keep behavior changes narrow and add focused tests using synthetic data. Do not reformat unrelated files.
- User-facing errors are concise, actionable Chinese. Swift errors use typed `Error`/`LocalizedError` where appropriate; Windows code preserves exception context and reports actionable failures. Never silently swallow persistence, import, update or user-requested operation errors. Best-effort cleanup may be non-fatal only when the user-visible operation remains safe.
- Preserve the raw draft text exactly, including whitespace and line endings. During IME composition do not replace editor controls, steal focus, or write an older snapshot back over current input.
- State clearly whether behavior is implemented, CI-tested, or verified on a real Windows device. Cross-compilation is not Windows UX validation.

## Golden commands

Run macOS commands from the repository root:

```bash
swift test
./scripts/build-app.sh
```

Run Windows commands in PowerShell from `windows/`:

```powershell
dotnet test .\tests\DraftBook.Core.Tests\DraftBook.Core.Tests.csproj -c Release
dotnet test .\tests\DraftBook.Windows.Tests\DraftBook.Windows.Tests.csproj -c Release
dotnet build .\src\DraftBook.Windows\DraftBook.Windows.csproj -c Release
```

Package commands create local artifacts and may require the matching OS/toolchain. Do not run release workflows or upload artifacts unless the user explicitly asks for publication. On a host without the required SDK, report that limitation instead of claiming verification.
