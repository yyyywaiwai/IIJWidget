# IIJWidget

IIJWidget は IIJmio 会員サイトの非公開 API を利用して高速通信量・請求サマリ・回線状態を取得し、SwiftUI アプリと iOS 17 以降のウィジェットで直感的に可視化する非公式ツールセットです。資格情報は端末のキーチェーンと App Group コンテナに保存され、アプリとウィジェットの双方で安全に共有されます。

## 特徴
- **SwiftUI アプリ (`IIJWidget/`)**: mioID とパスワードを保存し、残量カード・請求一覧・回線状態に加えて、会員サイト準拠の月別/日別データ利用量テーブルも 1 画面で確認できます。
- **ウィジェット拡張 (`RemainingDataWidget/`)**: アクセサリ/システムサイズごとのレイアウトを備え、30 分ごとに `WidgetDataStore` から最新スナップショットを読み込みます。iOS 17 では App Intents を使った手動リフレッシュにも対応。
- **共有レイヤー (`Shared/`)**: `IIJAPIClient`、`CredentialStore`、`WidgetRefreshService` などをまとめ、App Group と Keychain を通じてデータを再利用します。
- **CLI ツール (`Tools/IIJFetcher`)**: API エンドポイントの動作確認やデバッグに使える SwiftPM ベースのフェッチャーを同梱。`--mode usage` で月別、`--mode daily` で直近 30 日分の日別利用量を JSON 取得できます。
- **ドキュメント (`docs/`)**: `iij_endpoints.md` に主要 API とレスポンス項目を整理し、実装とスクリプトを同期しやすくしています。

## ディレクトリ構成
```text
IIJWidget/           # メインアプリ (SwiftUI ビュー、ViewModel、Assets)
RemainingDataWidget/ # WidgetKit エクステンションと intents 定義
Shared/              # API クライアント、資格情報ストア、モデル共通コード
Tools/IIJFetcher/    # Swift Package ベースの fetch CLI
IIJWidget.xcodeproj  # アプリ/ウィジェット各ターゲットを束ねる Xcode プロジェクト
docs/                # エンドポイント定義などの補助資料
```

## 動作要件
- macOS 14 以降 / Xcode 15 以降
- iOS 17 以降の実機またはシミュレータ（アクセサリウィジェット対応のため）
- IIJmio の mioID（または登録メールアドレス）とパスワード
- 任意の App Group と Keychain Sharing 設定（`Shared/AppGroup.swift` の `identifier` を自身のものに置き換えてください）

## セットアップ手順
1. リポジトリを取得: `git clone https://github.com/yyyywaiwai/IIJWidget.git`。
2. Xcode で `IIJWidget.xcodeproj` を開き、`Signing & Capabilities` で App Group / Keychain Sharing を有効化。`Shared/AppGroup.swift` の `group.jp.yyyywaiwai.iijwidget` を自身の App Group ID に更新します。
3. アプリをビルドして起動し、トップ画面のフォームから mioID / パスワードを入力。資格情報は `CredentialStore` 経由でキーチェーンに保存され、ウィジェット・CLI からも参照可能になります。
4. ウィジェットを追加する場合は、端末の Home 画面で「IIJWidget」を検索し、好みのサイズを追加してください。Widget は 30 分おきに自動更新し、iOS 17 以降ではウィジェット内の更新ボタンでもリフレッシュできます。
5. CLI で API を確認する場合:
   ```bash
   cd Tools/IIJFetcher
   # すべてのデータをまとめて取得
   swift run IIJFetcher --mode all --mio-id <ID> --password <PW>

   # 日別データ利用量だけを確認
   swift run IIJFetcher --mode daily --mio-id <ID> --password <PW>
   ```
   もしくは `IIJ_MIO_ID` / `IIJ_PASSWORD` を環境変数で渡せます。

## ビルド & テスト
- アプリ/ウィジェットのビルド: `xcodebuild -scheme IIJWidget -configuration Release`
- CLI のテスト (SwiftPM): `cd Tools/IIJFetcher && swift test`
- Xcode から `IIJWidget` または `RemainingDataWidget` スキームを選択してシミュレータで動作確認するのが最も簡単です。

## 開発メモ
- API 仕様の詳細は `docs/iij_endpoints.md` を参照してください。エンドポイントやレスポンス構造を更新した場合はドキュメントも合わせて更新します。
- `Shared/CredentialStore.swift` は Keychain のアクセルグループを自動移行するため、既存ユーザーでもウィジェットへシームレスに移行できます。
- `WidgetRefreshService` は App Group の共有ディレクトリに JSON スナップショットを保存し、ウィジェットがオフラインでも最後の成功値を表示できるようにしています。
- `Shared/DataUsageParser.swift` は `viewmonthlydata` / `viewdailydata` HTML を共通モデルにパースするための処理をまとめています。会員サイトのテーブル構造が変わった場合はここを更新してください。

## セキュリティ上の注意
- 資格情報や API トークンをリポジトリに含めないでください。`.gitignore` によってユーザー固有の設定ファイルは除外済みです。
- 非公式の内部 API を使用しているため、IIJmio 側の仕様変更により予告なく動作しなくなる可能性があります。`IIJAPIClient` のログで HTTP ステータスや `error` コードを確認してください。

## ライセンス
現時点ではライセンスを設定していません。公開・配布ポリシーを決定したら本 README を更新してください。
