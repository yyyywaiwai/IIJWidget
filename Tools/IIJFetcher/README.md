# IIJFetcher

アプリと同じ GAPI クライアント・30 日表クライアント・モデル・マージ処理を使う実通信検証 CLI と、共有ロジックのテスト用 Swift Package です。
アプリ／Widget の通常更新は GAPI のみで、30 日表は利用量タブを開いた時だけ取得します。CLI は両経路をまとめて検証します。
旧会員サイトの残量・請求・契約・月次取得や旧 CLI モードは削除済みです。

## ソースの共有方針

`Sources/IIJFetcher/IIJFetcher.swift` が CLI 固有のエントリーポイントです。
それ以外の本番 Swift ソースは、リポジトリ内の `Shared/` または `IIJWidget/` を参照する**相対シンボリックリンク**です。
リンク先の本番ソースを修正し、CLI 用コピーを追加しないでください。共有対象を増やす場合も同じ方式で追加します。

主な責務は次のように分離しています。

| 責務 | 本番ソース |
| --- | --- |
| GAPI の取得手順・セッション管理 | `Shared/MyIIJmioAPIClient.swift` |
| HTTP transport・ステータスエラー処理 | `Shared/GAPIHTTPClient.swift` |
| GAPI レスポンスのデコード | `Shared/GAPIResponseModels.swift` |
| アプリ用ペイロードへの変換 | `Shared/MyIIJmioPayloadMapper.swift` |
| 30 日表の取得・解析・GAPI データとのマージ | `Shared/ThirtyDayUsageClient.swift`、`DataUsageParser.swift`、`DailyUsageMerger.swift` |
| 更新時のキャッシュ再利用・履歴保持方針 | `Shared/PayloadRefreshPolicy.swift` |
| 同時更新の集約・待機・セッション切替 | `IIJWidget/ViewModel/RefreshCoordinator.swift` |
| チャートデータ集計・表示範囲・選択状態 | `Shared/Helpers/ChartDataBuilder.swift` |
| Widget スナップショット・ペイロード変換・タイムライン予定 | `Shared/WidgetSnapshot.swift`、`WidgetSnapshot+Payload.swift`、`WidgetTimelineSchedule.swift` |
| 使いすぎ通知の候補生成・重複抑止・配送処理 | `Shared/UsageAlerts.swift`、`UsageAlertDelivery.swift` |

SwiftUI の画面構成や WidgetKit の描画は SwiftPM テストの対象外です。共有ロジックと UI を分けて検証します。

## 自動検証

Swift Package は Swift 6.2 以上、macOS 13 以上を前提にしています。アプリ全体の検証には対応する Xcode も必要です。
リポジトリルートで実行します。

```sh
# 共有ロジックのテストだけを実行。実通信は行いません。
swift test --package-path Tools/IIJFetcher

# 共有ソース検査・テスト・回帰検査・差分検査・アプリビルドを順に実行。
Tools/validate.sh Debug

# Release 構成でも同じ検査を実行。
Tools/validate.sh Release
```

`Tools/validate.sh` は引数省略時に Debug を選び、次の順序で実行します。途中で失敗した場合は後続処理へ進みません。

1. `Tests/test_shared_source_links.py`：本番ソースへのリンクと参照先を検査。
2. `swift test --package-path Tools/IIJFetcher`：下記のネットワーク不要テストを実行。
3. `Tests/test_usage_chart_lifecycle.py`：月別・日別グラフの再表示処理をソース構造から検査。
4. `git diff --check`：差分の空白エラーを検査。
5. `xcodebuild -scheme MioWIdget -configuration Debug` または `Release`：アプリと Widget をビルドし、標準出力・標準エラーをルートの `build.log` に保存。

プロジェクト名は `IIJWidget`、アプリ scheme は **`MioWIdget`** です。Widget scheme は `RemainingDataWidget` です。
構成変更時は `xcodebuild -list -project IIJWidget.xcodeproj` で確認してください。

### テストの分類

| 分類 | 検証する内容 |
| --- | --- |
| 純粋な変換・解析 | 回線 ID、GAPI 数値と欠落フィールド、請求詳細、30 日表、日付正規化、GAPI 優先マージ、共有契約の重複排除 |
| 更新・保存方針 | 履歴再利用期限、回線変更時のマージ、表の分離保存、旧キャッシュの拒否 |
| モック通信 | GAPI のリクエスト順序・クエリ、認証／HTTP エラー、デコード失敗、transport エラー |
| 非同期更新制御 | 同時要求の集約、異なる要求の待機、呼び出し元キャンセル、セッション切替、失敗後の再試行 |
| チャートの純粋ロジック | 月別・日別・請求データの集計、表示範囲、選択状態、値や画面幅が変わった時の再構築 |
| Widget の純粋ロジック | スナップショット互換性、容量・残量の補完、更新中／成功状態、タイムライン予定 |
| 通知のロジック・配送制御 | 当日／当月と有効な測定値の判定、重複抑止、配送失敗後の再試行、並行更新 |
| ソース構造の回帰検査 | 共有ソース参照、30 日取得の呼び出し経路、チャート再表示時のアニメーション開始処理 |

テストには匿名化 fixture、モック transport、一時保存領域を使い、実アカウントへ通信しません。
純粋ロジックやモック通信のテスト成功は、実際の認証、OS による通知表示、Widget の描画・自動更新時刻を保証するものではありません。

### UI と実アカウントの確認

- **モック UI 検証**：Simulator／実機で画面遷移、グラフ再表示、設定保存、Widget の各サイズなどを確認します。ビルドやソース検査とは別の証拠として記録します。
- **実アカウント検証**：実際の認証とサーバーデータ取得を確認します。下記 CLI はこの検証に使い、自動検証スクリプトには含めていません。
- **OS 連携の確認**：通知許可・通知表示、App Group 共有、バックグラウンド更新、WidgetKit の実タイムラインはアプリ／Widget で別途確認します。モック UI や CLI の成功だけで実施済みにしないでください。

`.github/workflows/pr-firebase-distribution.yml` と `release-testflight.yml` は現在 Discord 通知のみを行います。
これらの workflow は、上記検証や Firebase App Distribution／TestFlight 配布を自動実行するものではありません。

## 実通信 CLI

```sh
# リポジトリルートから起動。
swift run --package-path Tools/IIJFetcher IIJFetcher
```

CLI 起動後に、標準入力の 1 行目へ mioID またはメールアドレス、2 行目へパスワードを入力します。
端末入力は非表示です。コマンド引数・ログ・リポジトリ内ファイルに資格情報を含めないでください。

成功時は `GAPI_30D_OK` と回線・請求・履歴件数のみを表示します。
Bearer token は Keychain へ保存せず、Cookie は一時セッションに限定し、実レスポンスをデバッグストアへ保存しません。
失敗時は非ゼロの終了コードを返し、取得済みの部分データを成功扱いしません。
