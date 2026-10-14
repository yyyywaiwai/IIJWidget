# プロジェクト構造と責務

## 対象とビルド単位

IIJWidget は、MyIIJmio の GAPI と補助的な30日履歴を表示する iOS / iPadOS アプリです。SwiftUI のアプリと WidgetKit 拡張が `Shared/` の実装を共有します。独立した macOS アプリターゲットはなく、macOS 用の補助ツールとして SwiftPM の IIJFetcher があります。

| 種別 | 名前 | 役割 |
| --- | --- | --- |
| Xcode プロジェクト | `IIJWidget.xcodeproj` | アプリ／拡張の設定 |
| アプリターゲット・共有スキーム | `MioWIdget` | `MioWidget.app` を生成し、拡張を組み込む |
| 拡張ターゲット・共有スキーム | `RemainingDataWidget` | ホーム画面・ロック画面ウィジェット |
| SwiftPM パッケージ | `Tools/IIJFetcher` | 実通信 CLI と本番ロジックのユニットテスト |

アプリと拡張の deployment target は iOS 17 です。パッケージは macOS 13 以降、Swift tools version 6.2 を指定しています。開発環境の OS / Xcode 条件は、利用する Xcode と SDK に合わせて確認してください。

## ディレクトリの地図

```text
IIJWidget/
├── IIJWidgetApp.swift           # @main、通知 delegate、ショートカット登録
├── ContentView.swift           # AppViewModel 所有、オンボーディング、更新・エラー導線
├── GetDataIntent.swift         # 更新済みデータを JSON として返す App Intent
├── RefreshDataIntent.swift     # 更新・通知判定の App Intent / App Shortcuts
├── Model/AppSection.swift      # タブの識別子・表示情報
├── ViewModel/
│   ├── AppViewModel.swift      # 認証入力、設定、取得結果、ユーザー操作の調整
│   ├── AppLoadState.swift      # 読み込み／成功／失敗と保持済み payload の表現
│   └── RefreshCoordinator.swift # 更新の合流・直列化・セッション無効化
└── Views/
    ├── Root/MainTabView.swift  # タブ構成、利用量タブ進入時の履歴取得
    ├── Onboarding/            # 初回設定と資格情報入力
    ├── Components/            # デザイン、チャート、スクリーンショット保護、フィードバック
    └── Tabs/
        ├── Home/              # 概要、回線カード、残量リング、チャート切替
        ├── Usage/             # 月別／日別、共通回線カード、利用量行、回線ステータス
        ├── Billing/           # 請求概要、グラフ、一覧、明細シートと明細カード
        └── Settings/          # 通知、表示、ログアウト、色選択、デバッグ画面

RemainingDataWidget/           # Provider、表示変換、サイズ別 View、更新操作
Shared/                        # API、モデル、ストレージ、更新方針、通知、時間計算
Tools/IIJFetcher/               # CLI エントリ、本番ソースへのリンク、SwiftPM テスト
Tools/validate.sh              # リポジトリの検証入口
Tests/                         # ソースリンクとチャート復帰の構造テスト
docs/                          # API 仕様と設計資料
.github/workflows/             # Discord 通知のみ
```

Xcode は `IIJWidget/`、`Shared/`、`RemainingDataWidget/` をファイルシステム同期グループとして扱います。共有コードは独立した framework target ではなく、アプリと拡張の各ターゲットへコンパイルされます。

## アプリの状態と画面

### 状態の所有者

- `ContentView` は `AppViewModel` とタブ選択・オンボーディング提示状態を所有します。
- `AppViewModel` は画面に必要な取得状態と永続化対象の設定を公開し、API の詳細や HTML のパースを扱いません。
- `AppLoadState.swift` の `AppViewModel.LoadState` は読み込み中・失敗時にも直前の `AggregatePayload` を保持できる形にしています。画面はエラーが出ただけで既存データを空表示へ戻しません。
- `RefreshCoordinator` は実行中更新への合流と、目的が異なる更新の順序を管理します。ログアウト時に世代を変更し、進行中・待機中の旧処理を無効化します。
- 設定変更は `AppViewModel` の更新メソッドから保存します。子 View が保存先を個別に書き換える設計にはしません。

### タブとコンポーネント

| 領域 | 入口と主な責務 |
| --- | --- |
| Home | `HomeDashboardTab` が構成を担当。`HomeOverviewHeader`、`ServiceInfoCard`、`ServiceUsageRing`、`UsageChartSwitcher` が表示を分担 |
| Usage | `UsageListTab` が幅に応じた配置と月別／日別選択を担当。`MonthlyUsageSection` / `DailyUsageSection` が単位別の判定を行い、`UsageServiceCard` / `UsageEntryRow` が共通表示を担当 |
| Billing | `BillingTabView` が配置とシート提示を担当。`BillingHighlightCard`、`BillingBarChart`、`BillSummaryList`、`BillDetailSheet` が責務を分担 |
| Settings | `SettingsTab` が既存更新メソッドと各節を接続。`UsageAlertSettingsSection`、`DisplaySettingsSection`、`SettingsLogoutSection` などが局所的な UI 状態を所有 |
| 通知許可 | `NotificationPermissionModel` が許可取得・照会を担当し、`NotificationPermissionRows` が状態を表示 |
| デバッグ | `DebugToolsViewModel` がキャッシュ・レスポンス・Cookie を読み込み、JSON の表示用整形を `reload()` 時に実行。各行と詳細画面は表示を担当 |

抽出した View には、読み取る値または変更する Binding を渡します。アプリ全体の状態の監視は必要な箇所に限定し、カード・行のためだけにモデル全体を渡さない方針です。

## API とデータ変換

| ファイル | 責務 |
| --- | --- |
| `Shared/MyIIJmioAPIClient.swift` | 認証、セッション利用、GAPI エンドポイントの呼び出し順序 |
| `Shared/GAPIHTTPClient.swift` | HTTP リクエスト、レスポンス検証、JSON の読み書き、認証トークンを除くデバッグ記録 |
| `Shared/GAPIResponseModels.swift` | GAPI レスポンスの DTO とデコード |
| `Shared/MyIIJmioPayloadMapper.swift` | DTO から `AggregatePayload`、回線、利用量、請求明細への変換 |
| `Shared/IIJModels.swift` | アプリ／ウィジェットで使うドメインモデル |
| `Shared/ThirtyDayUsageClient.swift` | 利用量タブ専用の30日表取得・会員サイトセッション |
| `Shared/DataUsageParser.swift` | 30日表 HTML から数値モデルへの変換、日付・通信量の正規化 |
| `Shared/DailyUsageMerger.swift` | 表の回線照合と GAPI 優先の統合 |
| `Shared/Helpers/ChartDataBuilder.swift` | 表示用チャート点の集計、順序、日付ラベル |

API の URL・パラメータ・レスポンス項目は [iij_endpoints.md](iij_endpoints.md) を参照してください。通信と変換を分けているため、DTO・マッピングは固定データで、HTTP 層は差し替えた `URLSession` のモック応答で検証できます。

## 更新と保存の流れ

### 通常の GAPI 更新

```text
アプリの更新操作 / Widget Provider / App Intent
    ↓
WidgetRefreshService
    ├── 保存済み token または資格情報で認証
    ├── MyIIJmioAPIClient → GAPIHTTPClient
    ├── GAPIResponseModels → MyIIJmioPayloadMapper
    ├── PayloadRefreshPolicy でキャッシュ・補助履歴を調整
    ├── AggregatePayloadStore へ保存
    ├── WidgetSnapshot(payload:) → WidgetDataStore へ保存
    └── 新たに取得した値で UsageAlertNotifier を実行
```

`PayloadRefreshPolicy` は通信・認証・保存から独立した計算です。同日のキャッシュ再利用、回線構成の一致判定、残量／日次だけの更新と既存月次・請求の合成、現存回線の補助履歴保持を担います。

アプリ側の通常更新と手動更新は GAPI 全体を取得します。ウィジェット更新は条件により残量／日次だけを取得しますが、同日の履歴がない場合・強制更新・月間通知のため新しい月次値が必要な場合・回線構成が変わった場合は全体取得へ切り替えます。

### 30日履歴の更新

`MainTabView` の利用量タブ進入 → `AppViewModel.refreshUsageHistory()` → `WidgetRefreshService.refreshUsageHistory()` → `ThirtyDayUsageClient` の経路で取得します。

- 結果は `AggregatePayload.thirtyDayUsage` に保存し、GAPI の `dailyUsage` や取得日時と混同しません。
- 表の取得前後でアカウントと回線構成を確認し、並行した GAPI 更新を古い payload で巻き戻さないよう、保存直前の最新 payload に履歴を反映します。
- 通常更新、ウィジェット更新、データ取得ショートカットから表を再取得しません。
- 表の取得失敗は、その時点の GAPI データを保持したままエラーとして扱います。

### ストレージ

| ファイル | 保存対象 |
| --- | --- |
| `CredentialStore` / `MyIIJmioTokenStore` | App Group 対応の Keychain に資格情報／GAPI セッション |
| `AggregatePayloadStore` | `gapi.payload.v2` のアプリ用キャッシュ |
| `WidgetDataStore` | `gapi.widget.snapshot.v2` のウィジェット用キャッシュ |
| `AccentColorStore` / `DisplayPreferencesStore` / `UsageAlertStore` | 色・表示・アラート設定 |
| `DebugResponseStore` / `RefreshLogStore` | デバッグ用応答と更新結果の履歴 |

旧形式キャッシュの読み込み・移行は行わず、GAPI を再取得します。デバッグデータには個人の契約・請求・通信量が含まれる可能性があるため、リポジトリへの追加や外部共有の前に内容を確認します。

## ウィジェットの責務

旧来の大きなモデル／画面ファイルではなく、次のように責務を分けて構成しています。

| ファイル | 責務 |
| --- | --- |
| `Shared/WidgetSnapshot.swift` | 表示用の保存モデルと値の導出 |
| `Shared/WidgetSnapshot+Payload.swift` | `AggregatePayload` から表示モデルへの変換 |
| `Shared/WidgetDataStore.swift` | スナップショットの保存・読み込み・更新中状態 |
| `Shared/WidgetTimelineSchedule.swift` | 次回更新要求時刻と成功表示の終了時刻の計算。WidgetKit 非依存 |
| `RemainingDataWidget/RemainingDataProvider.swift` | 更新結果／キャッシュから WidgetKit entry と timeline を構成 |
| `RemainingDataWidget/RemainingDataPresentation.swift` | snapshot と設定から表示用の値を組み立て |
| `RemainingDataWidget/RemainingDataHomeViews.swift` | Small／Medium の表示 |
| `RemainingDataWidget/RemainingDataAccessoryViews.swift` | ロック画面アクセサリの表示 |
| `RemainingDataWidget/RemainingDataMeters.swift` | 残量メーター |
| `RemainingDataWidget/WidgetRefreshControls.swift` | ホーム画面用の更新操作・状態表示 |
| `RemainingDataWidget/RefreshWidgetIntent.swift` | 手動更新とスナップショット状態の同期 |
| `RemainingDataWidget/ConfigurationAppIntent.swift` | ウィジェットごとの表示設定 |
| `RemainingDataWidget/RemainingDataWidget.swift` | family の振り分けと Widget 定義 |

自動更新間隔は `WidgetTimelineSchedule.refreshInterval` の30分です。これは WidgetKit に渡す再取得希望時刻であり、30分おきの実行保証ではありません。取得失敗時は保存済みの値を表示します。ロック画面はタップでアプリを開き、ホーム画面には更新インテントのボタンを残します。

## 使いすぎ通知とショートカット

- `UsageAlerts` は当日／当月の新しい数値と正のしきい値から通知候補を計算します。期間は日本時間です。
- `UsageAlertDelivery` は App Group 内の記録とファイルロックを使い、アプリ・Widget・Shortcuts 間の重複登録を抑えます。
- `UsageAlertNotifier` は通知許可、設定、アカウントの整合性を確認してローカル通知を登録します。通知登録の失敗は更新ログへ記録し、成功したデータ更新を失敗へ変更しません。
- 通知は更新時の判定です。モック、欠測、古い期間、30日表だけの取得は通知対象にしません。常時監視や APNs / Firebase サーバーによる通知ではありません。
- `RefreshDataIntent` は更新・ウィジェット再読み込み・通知判定を行います。`GetDataIntent` は同じ更新経路の結果を JSON テキストで返します。
- 「データを取得」は個人情報を返すため端末認証を要求します。資格情報・認証トークンは返しません。`thirtyDayUsage` は既存キャッシュのみを利用します。

通知済み記録は日次／月次の再登録を抑える仕組みであり、OS への登録直後にプロセスが終了する場合まで含めた厳密な一度限り配送の保証ではありません。実機での通知表示とロジックのテスト成功は区別します。

## 変更時に守る不変条件

1. **通常更新は GAPI のみ。** 30日表へのフォールバックや残量差分による当日推定を追加しません。
2. **回線 ID と単位を維持。** 回線は `lineServiceCode` で区別し、日次 MB／月次 GB の変換としきい値比較を混同しません。
3. **GAPI が優先。** 補助履歴は別保存し、同じ日の値は GAPI を優先します。失敗時に既存の正常な payload を消しません。
4. **旧セッションの完了を採用しない。** ログアウト・アカウント変更後に進行中処理が UI や履歴を戻さないよう、世代・資格情報・回線構成の確認を維持します。
5. **グラフの復帰を維持。** データ再構築だけでなく `onAppear` のアニメーション再開を残し、ホーム→別タブ→ホームの実表示を確認します。
6. **通知は新しい値だけ。** 当日／当月の欠測と古い値を除外し、通知登録失敗とデータ取得失敗を区別します。
7. **Widget の操作を変えない。** ロック画面はアプリ起動、ホーム画面は手動更新。自動更新の実行時刻を保証しません。
8. **共有ソースのコピーを作らない。** CLI とテストは本番ファイルへの相対リンクで同期し、変更はリンク先の本番ファイルへ行います。
9. **既存データと設定を保持。** 表示コンポーネントの分割でキャッシュキー・保存形式・通知許可・設定の永続化経路を変更しません。

## 検証の入口と証拠の範囲

```bash
# リポジトリルートから。引数省略時は Debug。
Tools/validate.sh Debug
Tools/validate.sh Release
```

このスクリプトはソースリンク確認 → SwiftPM テスト → チャート復帰の構造テスト → `git diff --check` → 指定構成の `MioWIdget` ビルドを順に実行します。ビルド詳細は `build.log` に保存します。署名設定や選択中の Xcode は実行環境側で整えてください。

- **SwiftPM テスト**: HTTP のモック応答、GAPI DTO・変換、30日表のパース／統合、更新調整、キャッシュ方針、チャート、通知候補・重複抑止、snapshot とタイムライン計算を検証します。IIJmio との実通信は行いません。
- **構造テスト**: `Tests/test_shared_source_links.py` と `Tests/test_usage_chart_lifecycle.py`。ソースの結び付きや復帰処理の存在を確認し、画面描画の成功までは保証しません。
- **ビルド**: アプリと拡張のコンパイルを確認します。インストール・起動・実通信・通知表示の証拠とは分けます。
- **モック UI**: `MockPayloadProvider.credentials` を使い、専用シミュレータでホーム、利用量、請求明細、設定、タブ復帰を確認します。GAPI と通知判定は実行されません。
- **実機・実アカウント**: ログイン、GAPI の値、30日表、App Group / Keychain 共有、ホーム画面の更新、ロック画面からの起動、通知、ショートカット出力を個別に確認します。非公開 API の現在の互換性はこの経路で確認します。

固定のテスト件数や特定の Simulator 名を成功条件にせず、実行したコミット・構成・端末・結果と、未検証の範囲を記録してください。

## CI と配布の現状

`.github/workflows/pr-firebase-distribution.yml` は PR 更新の Discord 通知、`release-testflight.yml` は `main` 更新の Discord 通知です。以前の配布経路名がファイル名に残っていますが、現行の内容には Xcode ビルド・ユニットテスト・Firebase 配布・TestFlight アップロードは含まれません。

通知には `DISCORD_WEBHOOK_URL` と Actions の `GITHUB_TOKEN` を使います。配布やリリースは別途署名・アーカイブ・アップロードを管理します。アプリ内で Firebase SDK を利用していないため、`GoogleService-Info.plist` は不要です。
