# Repository Guidelines
英語でthinkして日本語で出力すること
## Project Structure & Module Organization
- `IIJWidget/` hosts the main SwiftUI app and widget targets plus their asset catalogs and entitlements.
- `RemainingDataWidget/` contains the widget extension entry points, intents, and configuration lists for the data reminder.
- `Shared/` holds reusable services, API clients, models, and group helpers shared between app and widget.
- `Tools/IIJFetcher` is a Swift Package containing helper scripts (e.g., fetch commands) and should remain in sync with application APIs.
- `docs/` contains supporting references such as `iij_endpoints.md`; keep docs updated when you change endpoints or payload shapes.

## Build, Test, and Development Commands
- `xcodebuild -scheme IIJWidget -configuration Release`: builds the full app/widget targets; use for CI to verify compilation.
- `swift test` (from `Tools/IIJFetcher` if expanding the package): runs SwiftPM tests for the fetcher package; expect `Package.swift` to define targets before execution.
- Launch from Xcode (select scheme `IIJWidget` or `RemainingDataWidget`); the simulator run verifies entitlements and widget timelines in practice.

## Coding Style & Naming Conventions
- Swift files use 4-space indentation with the Swift API Design Guidelines: clarity over terseness, label all parameters that improve readability, and avoid force unwraps unless justified.
- File names match types (`AppViewModel.swift` for `AppViewModel`), and struct/class names start with uppercase CamelCase; private helpers use `fileprivate` or localized scope.
- Favor descriptive constants (e.g., `APIClient` methods that mirror endpoint names) and keep assets located in their respective `.xcassets` bundles.
- Use SwiftLint if adopted later; until then, enforce consistent formatting via Xcode’s default formatter and `Editor > Structure` checks.

## Testing Guidelines
- No automated widget tests exist yet; introduce XCTest targets in `IIJWidgetTests/` or widget-specific suites when adding logic-heavy features.
- Name test methods as `test<Feature>_<ExpectedBehavior>` (e.g., `testFetchRemainingData_success`), and keep fixtures in the `Shared` helpers if reusable.
- When creating mock responses, place sample JSON in `docs/` or `Tests/Fixtures` (create `Fixtures` when needed) to keep production code clean.

## Commit & Pull Request Guidelines
- Keep commits small and describe what changed, following the existing pattern: imperative tense (`Add gitignore`, `Update widget layout`).
- Each PR should include a short summary, testing steps taken (e.g., simulator run, `swift test` output), and note any outstanding manual checks (widget preview, app group access).
- Link issues or tickets in the description if applicable, and attach screenshots when UI/widget behavior changes.
- Rebase or squash locally so the final PR has a clear history; avoid merge commits unless the project specifically requests them.

## Security & Configuration Tips
- Store sensitive credentials outside of the repo; use app groups (`Shared/AppGroup.swift`) and Keychain-backed stores rather than hard coding tokens.
- Update `Shared/CredentialStore.swift` when API requirements change and note new entitlements (e.g., Background Modes) in the README or docs.
