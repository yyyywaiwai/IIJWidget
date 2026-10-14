# IIJWidget

IIJWidget は MyIIJmio の GAPI（非公開 API）を利用して、残データ量・請求・回線状態・通信量を表示する非公式の iOS / iPadOS アプリです。SwiftUI アプリと WidgetKit 拡張でデータを共有し、ローカル通知とショートカットによる更新にも対応しています。

Xcode プロジェクト名は `IIJWidget`、**アプリのターゲット／スキーム名は `MioWIdget`**、生成されるアプリは `MioWidget.app` です。

## 特徴

- **アプリ**: ホーム／利用量／請求／設定の各タブで、残量・月別／日別利用量・請求明細をカードと Swift Charts で表示します。手動更新・引っ張って更新・通常の自動更新は GAPI を使います。
- **補助的な30日履歴**: 利用量タブを開いた時にだけ30日表を取得します。GAPI の日次データとは分離して保存し、表示時に GAPI の値を優先して統合します。表の取得に失敗しても、保持済みの GAPI データは破棄しません。
- **ウィジェット**: ホーム画面の Small／Medium と、ロック画面の Inline／Circular／Rectangular に対応します。ホーム画面では手動更新、ロック画面ではタップによるアプリ起動を提供します。自動更新は約30分後の再取得を WidgetKit に要求しますが、実行時刻は iOS が決めます。
- **共有ロジック**: API 通信・レスポンス変換・キャッシュ方針・スナップショット・通知判定を `Shared/` に集約しています。資格情報と Bearer token は共有 Keychain、表示用キャッシュと設定は App Group で共有します。
- **CLI とテスト**: `Tools/IIJFetcher` は本番ソースへの相対シンボリックリンクを利用します。実通信 CLI と、匿名化したデータによるネットワーク非依存のユニットテストを分けています。

## ディレクトリ構成

```text
IIJWidget/                  # アプリのエントリ、状態管理、SwiftUI 画面、App Intents
  ViewModel/                # AppViewModel、AppLoadState、RefreshCoordinator
  Views/Tabs/               # Home / Usage / Billing / Settings の機能別コンポーネント
RemainingDataWidget/        # Provider、表示用変換、サイズ別 View、更新操作
Shared/                     # API・モデル・ストレージ・更新方針・通知・タイムライン計算
Tools/IIJFetcher/           # 実通信 CLI と共有ソースの SwiftPM テスト
Tools/validate.sh           # リンク整合性・ユニット／構造テスト・ビルドの一括実行
Tests/                      # 共有ソースリンクとチャート復帰処理の構造テスト
IIJWidget.xcodeproj/        # MioWIdget / RemainingDataWidget ターゲットと共有スキーム
docs/                       # 構成・責務・API の資料
.github/workflows/          # PR / main 更新の Discord 通知
```

責務の境界、更新の流れ、変更時に守る条件は [プロジェクト構造](docs/PROJECT-STRUCTURE.md) にまとめています。

## 動作要件

- iOS / iPadOS 17 以降の実機またはシミュレータ。
- iOS SDK と Swift 6.2 以降を備えた Xcode。`Tools/IIJFetcher/Package.swift` は `swift-tools-version: 6.2` を指定しています。
- CLI パッケージの対象は macOS 13 以降です。開発用 Mac の必要 OS は、利用する Xcode の対応条件に従ってください。このリポジトリに独立した macOS アプリターゲットはありません。
- 実データを取得する場合は IIJmio の mioID（または登録メールアドレス）とパスワード。
- App Group と Keychain Sharing の設定。

## セットアップ手順

1. リポジトリを取得します。
   ```bash
   git clone https://github.com/yyyywaiwai/IIJWidget.git
   cd IIJWidget
   ```
2. Xcode で `IIJWidget.xcodeproj` を開き、`MioWIdget` と `RemainingDataWidget` の署名設定を確認します。`Shared/AppGroup.swift` の App Group ID と両ターゲットの entitlements を一致させ、App Group / Keychain Sharing を有効にしてください。
3. スキーム `MioWIdget` でビルドして起動し、オンボーディングで資格情報を保存します。右上の「最新取得」または各タブの引っ張って更新で GAPI を取得できます。
4. Home／Lock 画面にウィジェットを追加します。手動更新ボタンはホーム画面用です。ロック画面のウィジェットはアプリを開きます。
5. CLI で実通信を確認する場合は、次を実行します。
   ```bash
   swift run --package-path Tools/IIJFetcher IIJFetcher
   # プロンプトなしで ID、パスワードを各1行ずつ入力（端末では非表示）
   ```
   GAPI と30日表の取得・回線照合・マージを検証します。資格情報をコマンド引数へ渡さないでください。詳細は [IIJFetcher README](Tools/IIJFetcher/README.md) を参照してください。

## データ管理

- 残量は GAPI の数値、回線識別は `lineServiceCode` を使用し、同一契約の複数 SIM を区別します。
- 利用量は GB / MB の数値として保存し、表示文字列と日付 ID はモデルから導出します。日付は統一表記に正規化します。
- `/usageFee` の請求詳細を `AggregatePayload.billDetails` に保持し、キャッシュにある明細の再取得を省きます。
- キャッシュキーは `gapi.payload.v2` / `gapi.widget.snapshot.v2` です。旧形式キャッシュの読み込み・変換はせず、再取得します。
- ウィジェットの通常更新では、条件が合えば同日の月次・契約・請求情報を再利用し、残量・当日利用量だけを取得します。日付・回線構成の変更、強制更新、有効な月間通知しきい値がある場合は全体取得へ切り替えます。この方針は `PayloadRefreshPolicy` にまとめています。
- 30日表は `thirtyDayUsage` に分離保存します。通常更新では現存する回線の履歴だけを保持し、`DailyUsageMerger` が GAPI 優先で表示用に統合します。残量差分から当日利用量を推定しません。
- アプリの更新要求は `RefreshCoordinator` が調整します。同じ目的の更新が実行中なら合流し、別の目的の更新は必要に応じて順番に実行します。ログアウト時に進行中の処理と待機中の処理を無効化し、旧セッションの結果が画面へ戻るのを防ぎます。

## 使いすぎ通知とショートカット

設定の「使いすぎアラート」を有効にし、日次／月次の正のしきい値（MB）を入力して通知を許可してください。
アプリ・ホーム画面ウィジェットの手動更新、ウィジェットの自動更新、ショートカットによるGAPI更新の成功時に、
当日／当月の取得済み高速・低速使用量の合計を回線ごとに判定します。30日表の取得だけでは通知しません。

- ショートカットアプリのMioWidgetに **「データを更新して使いすぎを確認」** を追加できます。アプリを開かずに更新し、ウィジェットも再読み込みします。先にアプリでログインと通知許可を済ませてください。
- **「データを取得」** は最新データをJSONテキストで返します。後続の「入力から辞書を取得」で、`top.serviceInfoList`（残量・容量はGB）、`dailyUsage`（MB）、`monthlyUsage`（GB）、`bill`などを利用できます。取得日時はISO 8601形式です。更新・ウィジェット再読み込み・使いすぎ通知も実行します。通知未許可でもデータは取得できます。
- 取得結果には電話番号・契約・請求情報を含むため、「データを取得」は端末の認証を必要とします。パスワードや認証トークンは含みません。出力を外部送信するショートカットの共有先には注意してください。`thirtyDayUsage`は既存キャッシュがある場合だけ含まれ、このアクションでは再取得しません。
- iOSのローカル通知を使用し、Firebase・APNsサーバーや資格情報の外部保存は追加しません。
- 通知はアカウント・回線ごとに日次／月次それぞれ1回。日本時間で期間を区切り、通知済み記録をApp Groupで共有します。しきい値変更やOFF→ONでは同じ期間の通知を繰り返しません。
- 月間しきい値が有効な場合、ウィジェット更新でも月次データを取得するため、通常よりAPIリクエストが増えます。欠測・古い期間・モックデータは通知対象外です。
- 通知が拒否されている場合もグラフの警告表示は有効です。設定画面からiOSの通知設定を開けます。通知登録の失敗は更新履歴に残し、データ更新自体は成功として扱います。
- 常時監視ではありません。ウィジェット更新やショートカット実行がない間は検知せず、通知の表示時刻は集中モードなどの設定にも左右されます。

## ビルドと検証

リポジトリのルートで実行します。

```bash
Tools/validate.sh          # Debug が既定
Tools/validate.sh Debug
Tools/validate.sh Release
```

スクリプトは次を順に実行し、失敗した時点で終了します。

1. `Tests/test_shared_source_links.py`：CLI が本番ソースを相対リンクで参照していることを確認。
2. `swift test --package-path Tools/IIJFetcher`：モデル、変換、HTTP モック、更新制御、通知・ウィジェット計算などのテスト。
3. `Tests/test_usage_chart_lifecycle.py`：タブ復帰時に棒グラフのアニメーションが再開する構造を確認。
4. `git diff --check`：差分の空白エラーを確認。
5. `xcodebuild -scheme MioWIdget -configuration Debug` または `Release`：アプリとウィジェットをビルド。詳細出力は `build.log` に保存。

個別に実行する場合は次のコマンドを使います。

```bash
swift test --package-path Tools/IIJFetcher
python3 Tests/test_shared_source_links.py
python3 Tests/test_usage_chart_lifecycle.py
xcodebuild -scheme MioWIdget -configuration Debug > build.log 2>&1
xcodebuild -scheme MioWIdget -configuration Release > build.log 2>&1
```

シミュレータを指定する場合は、先に利用可能な destination を確認します。端末名や OS バージョンを固定して想定しないでください。

```bash
xcodebuild -scheme MioWIdget -showdestinations
# 表示されたシミュレータの ID を指定
xcodebuild -scheme MioWIdget -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' build
```

### 検証結果の区別

| 検証 | 確認できる範囲 | 別途確認する範囲 |
| --- | --- | --- |
| SwiftPM テスト | 匿名化データによる計算、変換、更新制御、HTTP モック応答 | 現在の IIJmio API、実アカウントの認証 |
| 構造テスト | 本番ソースとのリンク、チャート復帰処理の存在 | 実際の描画やアニメーション |
| Xcode ビルド | アプリ／拡張のコンパイルと構成 | インストール、画面表示、通知配信 |
| モック UI | `MockPayloadProvider` の固定データによる各タブ、明細、設定、タブ復帰 | GAPI 実通信、実アカウントの値、使いすぎ通知 |
| 実機・実アカウント | ログイン、実データ取得、App Group / Keychain 共有、Widget 操作、通知・ショートカット | 他端末・他アカウント・将来の実行時刻 |

モック UI は `Shared/MockPayloadProvider.swift` の `credentials` で起動できます。モック更新は実通信と通知判定を行いません。既存アカウントの保存状態に影響するため、検証用シミュレータや専用の環境で利用してください。

UI 変更時はホーム→別タブ→ホームの復帰、日別／月別、請求明細の月切替、設定の保存・復帰を確認してください。実機でのウィジェットや通知は、ビルド成功・モック表示・純粋ロジックのテスト成功とは分けて記録します。

## GitHub Actions と配布

現在リポジトリにあるワークフローは **Discord 通知のみ**です。ファイル名には以前の配布経路名が残っています。

| ファイル | 実際の処理 |
| --- | --- |
| `.github/workflows/pr-firebase-distribution.yml` | `main` 向け PR の作成／更新など、または手動実行を Discord に通知。ドラフト PR は除外 |
| `.github/workflows/release-testflight.yml` | `main` への push、または手動実行を Discord に通知 |

これらは Xcode ビルド、ユニットテスト、Firebase App Distribution へのアップロード、TestFlight への送信を実行しません。検証は `Tools/validate.sh` などで別途実行し、配布は署名・アーカイブ・アップロードの手順を個別に管理してください。

現在の通知処理で設定する Secret は `DISCORD_WEBHOOK_URL` です。GitHub API 参照には Actions の `GITHUB_TOKEN` を使用します。App Store Connect / Firebase の配布用 Secret をこの通知ワークフローのために登録する必要はありません。

アプリ本体・ウィジェットは Firebase SDK を利用していないため、`GoogleService-Info.plist` は不要です。

## 開発メモ

- API のエンドポイントやペイロードを変更したら、[API 資料](docs/iij_endpoints.md)、共有モデル・変換処理、CLI とテストを同時に更新します。
- HTTP 処理は `GAPIHTTPClient`、レスポンス型は `GAPIResponseModels`、画面用モデルへの変換は `MyIIJmioPayloadMapper`、認証とエンドポイントの組み立ては `MyIIJmioAPIClient` が担います。
- `WidgetSnapshot`、`WidgetDataStore`、`WidgetSnapshot+Payload`、`WidgetTimelineSchedule` はモデル・保存・変換・時間計算を分担します。WidgetKit に依存しない計算は SwiftPM から検証します。
- `Tools/IIJFetcher/Sources/IIJFetcher` に共有コードのコピーを追加しないでください。`Shared/` または対象の本番ファイルへの相対シンボリックリンクを追加します。
- `DataUsageParser` は30日表の HTML 専用です。GAPI の通常取得へ HTML 取得フォールバックを追加しないでください。

## セキュリティ上の注意

- 資格情報・API トークン・個人の実レスポンスをリポジトリへ含めないでください。`.gitignore` は保護の補助であり、コミット前に差分を確認します。
- アプリのデバッグ画面・レスポンスキャッシュ・「データを取得」の出力には電話番号や請求情報などが含まれます。スクリーンショットやログの共有時は内容を確認してください。CLI は資格情報を標準入力で受け取り、トークンや実レスポンスを永続化しません。
- 非公開 API のため、IIJmio 側の仕様変更で動作が変わる可能性があります。テスト成功だけで実サービスとの互換性を判断しないでください。

## ライセンス

© 2025 yyyywaiwai. 本プロジェクトは [MIT License](./LICENSE) の下で提供されます。
