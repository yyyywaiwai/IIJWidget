# IIJWidget

IIJWidget は MyIIJmio の GAPI（非公開 API） を利用して高速通信量・請求サマリ・回線状態を取得し、SwiftUI アプリと iOS 17 以降のウィジェットで直感的に可視化する非公式ツールセットです。資格情報とBearer tokenは共有キーチェーンに保存され、アプリとウィジェットの双方で安全に共有されます。

## 特徴
- **SwiftUI アプリ (`IIJWidget/`)**: ホーム／利用量／請求／設定タブで `AggregatePayload` の残量・請求・回線状態・月別/日別利用量をカードと Swift Charts で可視化。最新月または任意の月をタップすると請求明細 (サプライ料・通話料などの内訳) も確認でき、右上の「最新取得」ボタンからGAPIによる一括更新をいつでも実行できます。当日を含む日別実測値はGAPI、30日表は利用量タブを開くたびに取得します。旧方式切替・取得フォールバック・残量差分による当日推定は削除しました。
- **ウィジェット拡張 (`RemainingDataWidget/`)**: ロック画面アクセサリ (Inline/Circular/Rectangular) とシステム Small/Medium を備え、App Intents (`RefreshWidgetIntent`) を使った手動リフレッシュと 30 分ごとの自動更新を両立。`WidgetDataStore` のスナップショット共有でオフライン時も最新値を表示します。
- **共有レイヤー (`Shared/`)**: `MyIIJmioAPIClient`、`ThirtyDayUsageClient`、`DataUsageParser`、`WidgetRefreshService`、`CredentialStore`、`WidgetDataStore` を App Group 経由で共有し、アプリ・ウィジェットが同じ数値モデルとキャッシュを扱います。CLIも共有ソースを直接ビルドし、認証情報やレスポンスは保存しません。
- **CLI ツール (`Tools/IIJFetcher`)**: GAPIと30日表の実通信検証。資格情報は標準入力から読み、成功時は件数だけを表示します。旧取得モードはありません。
- **ドキュメント (`docs/`)**: `iij_endpoints.md` に主要エンドポイントとレスポンス項目を整理。API のパラメータやペイロードを更新したら README / docs / CLI を必ず同期します。

## ディレクトリ構成
```text
IIJWidget/           # メインアプリ (タブ UI、ViewModel、オンボーディング、Assets、entitlements)
RemainingDataWidget/ # WidgetKit エクステンションと App Intents / タイムライン定義
Shared/              # API クライアント、CredentialStore、WidgetRefreshService、DataUsageParser などの共有コード
Tools/IIJFetcher/    # SwiftPM ベースの fetch CLI と HTML パーサ
IIJWidget.xcodeproj  # アプリ/ウィジェット各ターゲットを束ねる Xcode プロジェクト
docs/                # API 仕様や補助資料 (例: iij_endpoints.md)
```

## 動作要件
- macOS 14.5 以降 / Xcode 16 以降（CI では Xcode 26.0、Swift 6.2 ツールチェーン。`Tools/IIJFetcher` は `swift-tools-version: 6.2` を要求します）
- iOS 17 以降の実機またはシミュレータ。
- IIJmio の mioID（または登録メールアドレス）とパスワード
- App Group および Keychain Sharing 設定（`Shared/AppGroup.swift` の `identifier` を自身の App Group ID に更新し、両ターゲットの entitlements に追加してください）

## セットアップ手順
1. リポジトリを取得: `git clone https://github.com/yyyywaiwai/IIJWidget.git && cd IIJWidget`。
2. Xcode で `IIJWidget.xcodeproj` を開き、`Signing & Capabilities` で App Group / Keychain Sharing を有効化。`Shared/AppGroup.swift` の `group.jp.yyyywaiwai.miowidgetgroup` を自身の App Group ID に更新し、両ターゲットの entitlements と一致させます。
3. アプリをビルドして起動するとオンボーディングが表示されるので、注意事項に同意後、資格情報を入力して保存します。保存後は設定タブまたは画面右上の「最新取得」で `WidgetRefreshService` による残量/請求/回線状態/利用量の一括取得を実行できます。
4. ウィジェットを追加する場合は、端末の Home/Lock 画面で「IIJWidget」を選び、アクセサリ／Small／Medium の好きなサイズを追加してください。ウィジェットは 30 分おきに `WidgetDataStore` から更新し、`RefreshWidgetIntent` ボタンで手動リフレッシュが可能です。
5. CLI で API を確認する場合:
   ```bash
   cd Tools/IIJFetcher
   swift run IIJFetcher
   # プロンプトなしでID、パスワードを各1行ずつ入力（端末では非表示）
   ```
   GAPIと30日表の取得・回線照合・マージを検証します。資格情報をコマンド引数に渡さないでください。

## データ管理
- 残量はGAPIの数値、回線識別は`lineServiceCode`を使用し、同一契約の複数SIMを区別します。
- 利用量はGB/MBの数値だけを保存し、表示文字列とIDの重複保存を廃止しました。日付は統一表記に正規化します。
- `/usageFee`の請求詳細を同じキャッシュに保持し、詳細表示時の再取得を省きます。
- 新キャッシュは`gapi.payload.v2` / `gapi.widget.snapshot.v2`。旧キャッシュの読み込み・変換は行わず初回に再取得します。
- 更新ボタン・引っ張って更新・自動更新・WidgetはGAPIだけを取得します。Widgetは同日のGAPI月次・契約・請求を再利用し、日付・回線構成が変わるとGAPI全体を取得します。
- 30日表は利用量タブを開いた時だけ取得し、`thirtyDayUsage`にGAPIの日次と分けて保存します。通常更新では現存する回線の表を保持し、表示時にGAPI優先で統合します。表の取得失敗はGAPI更新を失敗させません。

## ビルド & テスト
- リリースビルド (CI 想定): `xcodebuild -scheme MioWIdget -configuration Release`
- シミュレータ検証: `xcodebuild -scheme MioWIdget -destination 'platform=iOS Simulator,name=iPhone 16e,OS=26.0' build`
- CLI のテスト (SwiftPM): `cd Tools/IIJFetcher && swift test`
- 実機/シミュレータ動作確認: Xcode で `MioWIdget` または `RemainingDataWidget` スキームを選択し、App Group・Widget タイムライン・`RefreshWidgetIntent` が正しく動作するか確認してください。

## CI / Firebase App Distribution
PR を `main` ブランチへ作成または更新すると、`.github/workflows/pr-firebase-distribution.yml` が自動で走り、Xcode 26.0 の `IIJWidget` Release アーカイブを生成して Firebase App Distribution にアップロードし、完了後に Discord Webhook へインストールリンクを投稿します (ドラフト PR はスキップ)。

### 必要な GitHub Secrets
| Secret 名 | 用途 |
| --- | --- |
| `ASC_API_KEY_ID` | App Store Connect API Key の Key ID |
| `ASC_API_KEY_ISSUER_ID` | App Store Connect API Key の Issuer ID |
| `ASC_API_KEY_P8` | App Store Connect API Key (`.p8`) を Base64 化した文字列 |
| `APPLE_TEAM_ID` | Apple Developer Team ID (例: `ABCDE12345`) |
| `FIREBASE_APP_ID` | Firebase App Distribution の iOS App ID (`1:1234567890:ios:abcdef`) |
| `FIREBASE_SERVICE_ACCOUNT` | App Distribution API 用サービスアカウント JSON 全文 |
| `FIREBASE_DISTRIBUTION_GROUPS` | 配布先のグループをカンマ区切りで指定 (不要なら空にできます) |
| `FIREBASE_DISTRIBUTION_TESTERS` | 個別テスターのメールアドレス (グループ未使用時に利用) |
| `DISCORD_WEBHOOK_URL` | 成果物リンクを通知する Discord Webhook URL |

`EXPORT_METHOD` はデフォルトで `development` に設定しています。AdHoc や Enterprise で配布する場合は workflow の `env` を任意のメソッドへ変更してください。Firebase へのアップロードが成功すると、`wzieba/Firebase-Distribution-Github-Action` の出力を使って Discord に `[Install build](...)` の埋め込みメッセージが送信されます。コード署名は Xcode の Automatically manage signing と App Store Connect API Key (Cloud Signing) で行うため、`.p8` キーを Secrets に登録すれば証明書やプロビジョニングプロファイルを配布する必要はありません。

### Firebase SDK について
アプリ本体・ウィジェット共に Firebase App SDK を利用していないため、`GoogleService-Info.plist` の設置や CI での復元手順は不要です。Firebase 関連の Secrets は App Distribution 用 (`FIREBASE_APP_ID` / `FIREBASE_SERVICE_ACCOUNT` など) のみ設定してください。

## 開発メモ
- API 仕様の詳細は `docs/iij_endpoints.md` を参照し、エンドポイントやレスポンス構造を変更した際は README・CLI・ドキュメントを同時に更新します。
- `Shared/CredentialStore.swift` は App Group 付きの Keychain へ資格情報を退避し、既存ユーザーの移行や CLI/Widget からの再利用を自動化しています。
- `WidgetRefreshService` と `WidgetSnapshot+Payload.swift` で `AggregatePayload` を `WidgetDataStore` のスナップショットへ変換し、`RefreshWidgetIntent` 実行時は `isRefreshing` フラグを同期します。ウィジェット更新ロジックを変更する場合は併せて見直してください。
- `Shared/DataUsageParser.swift` は 30日表の `viewdailydata` HTML から共通モデルを生成します。会員サイトのフォームやテーブル構造が変わった場合はここを更新してください。

## セキュリティ上の注意
- 資格情報や API トークンをリポジトリに含めないでください。`.gitignore` によってユーザー固有の設定ファイルは除外済みです。
- 非公式の内部 API を使用しているため、IIJmio 側の仕様変更により予告なく動作しなくなる可能性があります。`MyIIJmioAPIClient` / `ThirtyDayUsageClient` のログで HTTP ステータスや `error` コードを確認してください。

## ライセンス
© 2025 yyyywaiwai. 本プロジェクトは [MIT License](./LICENSE) の下で提供されます。
