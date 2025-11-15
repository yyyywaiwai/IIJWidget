# IIJWidget

IIJWidget は IIJmio 会員サイトの非公開 API を利用して高速通信量・請求サマリ・回線状態を取得し、SwiftUI アプリと iOS 17 以降のウィジェットで直感的に可視化する非公式ツールセットです。資格情報は端末のキーチェーンと App Group コンテナに保存され、アプリとウィジェットの双方で安全に共有されます。

## 特徴
- **SwiftUI アプリ (`IIJWidget/`)**: ホーム／利用量／請求／設定タブで `AggregatePayload` の残量・請求・回線状態・月別/日別利用量をカードと Swift Charts で可視化。最新月または任意の月をタップすると請求明細 (サプライ料・通話料などの内訳) も確認でき、右上の「最新取得」ボタンから `WidgetRefreshService` による一括更新をいつでも実行できます。
- **ウィジェット拡張 (`RemainingDataWidget/`)**: ロック画面アクセサリ (Inline/Circular/Rectangular) とシステム Small/Medium を備え、App Intents (`RefreshWidgetIntent`) を使った手動リフレッシュと 30 分ごとの自動更新を両立。`WidgetDataStore` のスナップショット共有でオフライン時も最新値を表示します。
- **共有レイヤー (`Shared/`)**: `IIJAPIClient`、`DataUsageParser`、`WidgetRefreshService`、`CredentialStore`、`WidgetDataStore` を App Group 経由で共有し、アプリ・ウィジェット・CLI が同じ `AggregatePayload` とセッションを扱えるようにしています。
- **CLI ツール (`Tools/IIJFetcher`)**: SwiftPM 製の `IIJFetcher` が `--mode top|bill|status|usage|daily|bill-detail|all` をサポート。`--mode all` は `{"fetchedAt","top","bill","serviceStatus","monthlyUsage","dailyUsage"}` 形式でまとめて取得でき、環境変数 (`IIJ_MIO_ID` / `IIJ_PASSWORD`) でも資格情報を渡せます。
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
2. Xcode で `IIJWidget.xcodeproj` を開き、`Signing & Capabilities` で App Group / Keychain Sharing を有効化。`Shared/AppGroup.swift` の `group.jp.yyyywaiwai.iijwidget` を自身の App Group ID に更新し、両ターゲットの entitlements と一致させます。
3. アプリをビルドして起動するとオンボーディングが表示されるので、注意事項に同意後、資格情報を入力して保存します。保存後は設定タブまたは画面右上の「最新取得」で `WidgetRefreshService` による残量/請求/回線状態/利用量の一括取得を実行できます。
4. ウィジェットを追加する場合は、端末の Home/Lock 画面で「IIJWidget」を選び、アクセサリ／Small／Medium の好きなサイズを追加してください。ウィジェットは 30 分おきに `WidgetDataStore` から更新し、`RefreshWidgetIntent` ボタンで手動リフレッシュが可能です。
5. CLI で API を確認する場合:
   ```bash
   cd Tools/IIJFetcher
   # すべてのデータをまとめて取得
   swift run IIJFetcher --mode all --mio-id <ID> --password <PW>

   # 個別 API
   swift run IIJFetcher --mode top      # /api/member/top
   swift run IIJFetcher --mode bill     # /api/member/getBillSummary
   swift run IIJFetcher --mode status   # /api/member/getServiceStatus
   swift run IIJFetcher --mode usage    # /service/setup/hdc/viewmonthlydata/
   swift run IIJFetcher --mode daily    # /service/setup/hdc/viewdailydata/
   # 個別請求明細 (最新月 or --month YYYYMM / --bill-no <番号>)
   swift run IIJFetcher --mode bill-detail --month 202510
   swift run IIJFetcher --mode bill-detail --bill-no 111005999429
   ```
   `IIJ_MIO_ID` / `IIJ_PASSWORD` 環境変数でも資格情報を渡せ、`--mode all` は `fetchedAt/top/bill/serviceStatus/monthlyUsage/dailyUsage` を 1 つの JSON に含めます。

## ビルド & テスト
- リリースビルド (CI 想定): `xcodebuild -scheme IIJWidget -configuration Release`
- シミュレータ検証: `xcodebuild -scheme IIJWidget -destination 'platform=iOS Simulator,name=iPhone 16e,OS=26.0' build`
- CLI のテスト (SwiftPM): `cd Tools/IIJFetcher && swift test`
- 実機/シミュレータ動作確認: Xcode で `IIJWidget` または `RemainingDataWidget` スキームを選択し、App Group・Widget タイムライン・`RefreshWidgetIntent` が正しく動作するか確認してください。

## CI / Firebase App Distribution
PR を `main` ブランチへ作成または更新すると、`.github/workflows/pr-firebase-distribution.yml` が自動で走り、Xcode 26.0 の `IIJWidget` Release アーカイブを生成して Firebase App Distribution にアップロードし、完了後に Discord Webhook へインストールリンクを投稿します (ドラフト PR はスキップ)。
証明書の上限に達した際は、ワークフローが App Store Connect API を通じて古い Apple Distribution 証明書を自動的に失効させ、Cloud Signing が常に新しい証明書を発行できるようにしています。CI で維持したい証明書がある場合は `ASC_PROTECTED_CERT_SERIALS` または `ASC_PROTECTED_CERT_NAMES` に登録することで、対象証明書を自動失効から除外できます。

### 必要な GitHub Secrets
| Secret 名 | 用途 |
| --- | --- |
| `ASC_API_KEY_ID` | App Store Connect API Key の Key ID |
| `ASC_API_KEY_ISSUER_ID` | App Store Connect API Key の Issuer ID |
| `ASC_API_KEY_P8` | App Store Connect API Key (`.p8`) を Base64 化した文字列 |
| `APPLE_TEAM_ID` | Apple Developer Team ID (例: `ABCDE12345`) |
| `ASC_PROTECTED_CERT_SERIALS` *(任意)* | 失効させたくない証明書のシリアル番号を JSON 配列 or カンマ/改行区切りで列挙 |
| `ASC_PROTECTED_CERT_NAMES` *(任意)* | 失効対象から除外する証明書名を JSON 配列 or カンマ/改行区切りで列挙 |
| `FIREBASE_APP_ID` | Firebase App Distribution の iOS App ID (`1:1234567890:ios:abcdef`) |
| `FIREBASE_SERVICE_ACCOUNT` | App Distribution API 用サービスアカウント JSON 全文 |
| `FIREBASE_DISTRIBUTION_GROUPS` | 配布先のグループをカンマ区切りで指定 (不要なら空にできます) |
| `FIREBASE_DISTRIBUTION_TESTERS` | 個別テスターのメールアドレス (グループ未使用時に利用) |
| `DISCORD_WEBHOOK_URL` | 成果物リンクを通知する Discord Webhook URL |

`EXPORT_METHOD` はデフォルトで `development` に設定しています。AdHoc や Enterprise で配布する場合は workflow の `env` を任意のメソッドへ変更してください。Firebase へのアップロードが成功すると、`wzieba/Firebase-Distribution-Github-Action` の出力を使って Discord に `[Install build](...)` の埋め込みメッセージが送信されます。コード署名は Xcode の Automatically manage signing と App Store Connect API Key (Cloud Signing) で行うため、`.p8` キーを Secrets に登録すれば証明書やプロビジョニングプロファイルを配布する必要はありません。

### ローカル開発での Firebase 設定
アプリ本体では Firebase iOS SDK を利用していないため、ローカルで `GoogleService-Info.plist` を配置する作業は不要です。Firebase App Distribution 用のシークレット（`FIREBASE_APP_ID` と `FIREBASE_SERVICE_ACCOUNT` など）だけを準備してください。

## 開発メモ
- API 仕様の詳細は `docs/iij_endpoints.md` を参照し、エンドポイントやレスポンス構造を変更した際は README・CLI・ドキュメントを同時に更新します。
- `Shared/CredentialStore.swift` は App Group 付きの Keychain へ資格情報を退避し、既存ユーザーの移行や CLI/Widget からの再利用を自動化しています。
- `WidgetRefreshService` と `WidgetSnapshot+Payload.swift` で `AggregatePayload` を `WidgetDataStore` のスナップショットへ変換し、`RefreshWidgetIntent` 実行時は `isRefreshing` フラグを同期します。ウィジェット更新ロジックを変更する場合は併せて見直してください。
- `Shared/DataUsageParser.swift` は `viewmonthlydata` / `viewdailydata` HTML から共通モデルを生成します。会員サイトのフォームやテーブル構造が変わった場合はここを更新してください。

## セキュリティ上の注意
- 資格情報や API トークンをリポジトリに含めないでください。`.gitignore` によってユーザー固有の設定ファイルは除外済みです。
- 非公式の内部 API を使用しているため、IIJmio 側の仕様変更により予告なく動作しなくなる可能性があります。`IIJAPIClient` のログで HTTP ステータスや `error` コードを確認してください。

## ライセンス
© 2025 yyyywaiwai. 本プロジェクトは [MIT License](./LICENSE) の下で提供されます。
