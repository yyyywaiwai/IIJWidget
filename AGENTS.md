# Repository Guidelines
英語でthinkして日本語で出力すること
## Project Structure & Module Organization
- `IIJWidget/` contains the SwiftUI app, assets, and entitlements. `Views/Tabs/` composes feature screens from smaller views; `ViewModel/` owns app state and refresh coordination.
- `RemainingDataWidget/` contains the WidgetKit extension, intents, provider, and family-specific views.
- `Shared/` contains production code shared by the app and widget: GAPI transport/response decoding/payload mapping, refresh policies, stores, notification logic, and widget snapshots/timeline scheduling. `Shared/Helpers/` contains chart data and state logic.
- `Tools/IIJFetcher/` is a Swift Package for an explicit live-account CLI and network-free tests. Except for the CLI entry point, production Swift sources are relative symlinks into `Shared/` or `IIJWidget/`; edit the linked source, never add a drifting copy.
- `Tests/` contains source-structure regression checks. `Tools/IIJFetcher/Tests/IIJFetcherTests/` contains SwiftPM tests.
- `docs/` contains supporting references such as `iij_endpoints.md`; keep docs updated when endpoints or payload shapes change.

## Build, Test, and Development Commands
- 実在するアプリ scheme は `MioWIdget`、Widget scheme は `RemainingDataWidget`。プロジェクト名 `IIJWidget` と区別し、構成変更時は `xcodebuild -list -project IIJWidget.xcodeproj` で確認する。
- 作業完了時はリポジトリルートで `Tools/validate.sh Debug` を実行する。Release 構成は `Tools/validate.sh Release`。引数省略時は Debug。
- `Tools/validate.sh` は共有ソースリンク検査 → `swift test --package-path Tools/IIJFetcher` → チャート再表示のソース回帰検査 → `git diff --check` → Xcode ビルドを順に実行し、失敗時はそこで停止する。
- ビルドのみを確認する場合は `xcodebuild -scheme MioWIdget -configuration Debug > build.log 2>&1`。Release は `-configuration Release` に置き換える。検証スクリプトもビルド出力をルートの `build.log` に保存する。
- Xcode からアプリを起動するときは `MioWIdget`、Widget を確認するときは `RemainingDataWidget` を選択する。ビルド成功と実際の画面・App Group・Widget タイムラインの動作確認は別々に記録する。
- コマンド実行は、その環境の権限・サンドボックスポリシーに従う。承認が必要な環境では承認を取得し、承認要求を許可しない環境では不要な権限昇格を指定しない。
- `.github/workflows/pr-firebase-distribution.yml` と `release-testflight.yml` は現在 Discord 通知専用。ファイル名から自動ビルド・テスト・Firebase/TestFlight 配布が行われると判断しない。

## Coding Style & Naming Conventions
- Swift files use 4-space indentation with the Swift API Design Guidelines: clarity over terseness, label all parameters that improve readability, and avoid force unwraps unless justified.
- File names match types (`AppViewModel.swift` for `AppViewModel`), and struct/class names start with uppercase CamelCase; private helpers use `fileprivate` or localized scope.
- Favor descriptive constants (e.g., `APIClient` methods that mirror endpoint names) and keep assets located in their respective `.xcassets` bundles.
- Use SwiftLint if adopted later; until then, enforce consistent formatting via Xcode’s default formatter and `Editor > Structure` checks.

## Testing Guidelines
- 純粋ロジックのテストは `Tools/IIJFetcher/Tests/IIJFetcherTests/` に追加する。対象にはレスポンス変換、利用量マージ、更新ポリシー、チャート集計・選択状態、Widget スナップショット・タイムライン予定、通知判定が含まれる。
- 同パッケージの通信テストは注入したモック transport、更新制御・通知配送のテストは制御可能な代替処理や一時保存領域を使う。`swift test` は実アカウントへの通信や OS による通知表示の証明ではない。
- `python3 Tests/test_shared_source_links.py` と `python3 Tests/test_usage_chart_lifecycle.py` はソース構造の回帰検査。後者の成功だけで、ホーム復帰時のグラフアニメーションが実画面で動いたと判断しない。
- モック UI 検証では Simulator/実機で画面遷移、グラフ再表示、設定保存、Widget 各サイズなどを確認する。実アカウントの認証、サーバー取得結果、実通知、バックグラウンド更新は別の検証として扱い、実施範囲を明記する。
- `swift run --package-path Tools/IIJFetcher IIJFetcher` は明示的な実通信検証用。通常の自動検証経路には含めず、資格情報は標準入力で渡す。成功しても Widget UI や OS の背景実行を検証したことにはならない。
- Name test methods as `test<Feature>_<ExpectedBehavior>` (e.g., `testFetchRemainingData_success`). Put reusable anonymized JSON in `Tests/Fixtures/` rather than embedding production account data.
- SwiftUI/WidgetKit の描画や操作を自動化する場合は、純粋ロジックのテストと分けて XCTest/UI test targets を設ける。未実施の手動確認を成功扱いしない。

## Commit & Pull Request Guidelines
- Keep commits small and describe what changed, following the existing pattern: imperative tense (`Add gitignore`, `Update widget layout`).
- Each PR should include a short summary, testing steps taken (e.g., simulator run, `swift test` output), and note any outstanding manual checks (widget preview, app group access).
- Link issues or tickets in the description if applicable, and attach screenshots when UI/widget behavior changes.
- Rebase or squash locally so the final PR has a clear history; avoid merge commits unless the project specifically requests them.

## Security & Configuration Tips
- Store sensitive credentials outside of the repo; use app groups (`Shared/AppGroup.swift`) and Keychain-backed stores rather than hard coding tokens.
- Update `Shared/CredentialStore.swift` when API requirements change and note new entitlements (e.g., Background Modes) in the README or docs.
- アプリ・Widget は Firebase SDK を参照しないため `GoogleService-Info.plist` は不要。配布サービスとアプリ内通知を混同せず、現行 workflow の処理を確認する。
