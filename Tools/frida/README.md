# MyIIJmio Frida 調査ツール

USB 接続した iOS 端末上の MyIIJmio 公式アプリ
（`jp.ad.iij.my-iijmio`）を観測するための Frida スクリプトです。

## 前提

- 端末が Frida 接続可能な状態であること（frida-server または同等の環境）。
- Mac と端末が USB 接続され、ペアリング・ロック解除済みであること。
- Mac 側の Frida client と端末側 server に互換性があること。

Mac 側の CLI は、グローバル Python を汚さないよう `uv tool` で導入できます。

```sh
uv tool install --python 3.12 frida-tools
frida-ps -Uai
```

MyIIJmio が起動済みなら、次のコマンドで観測できます。

```sh
frida -U -N jp.ad.iij.my-iijmio \
  -q \
  -l Tools/frida/myiijmio_network_observer.js \
  -t 3600
```

RootHide 等の環境では `frida -f` または spawn gating の resume が失敗する場合があります。その場合は
アプリを通常起動し、bundle identifier へすぐアタッチしてください。

## `myiijmio_network_observer.js`

次を観測します。

- `NSURLSession` のリクエスト開始と completion handler。
- React Native の `RCTHTTPRequestHandler` / `RCTMultipartDataTask` delegate。
- `WKWebView` と `ASWebAuthenticationSession` の遷移。

出力では次の値を保持しません。

- `Authorization`、Cookie、subscriber token などのヘッダー値。
- URL query の値。
- JSON / form の値。
- mioID、電話番号、service code、請求金額などの個人・契約情報。

JSON はキー、型、文字列長、配列件数だけを `[IIJ-FRIDA]` の JSON Lines として出力します。

## `myiijmio_readonly_probe.js`

公式アプリが送信した Bearer ヘッダーを端末プロセス内だけで再利用し、次の読み取り専用 GET を順番に確認します。

- `/lineInfo`
- `/contract`
- `/usageFee`
- `/dataTraffic`
- `/pastDataTraffic`

token 値は出力せず、レスポンスもキーと型だけを `[IIJ-PROBE]` として出力します。
この probe は、アタッチ後に公式アプリが GAPI リクエストを1回送信すると開始します。

```sh
frida -U -N jp.ad.iij.my-iijmio \
  -q \
  -l Tools/frida/myiijmio_readonly_probe.js \
  -t 3600
```

次の API は状態変更またはセッション変更を伴うため、readonly probe からは呼びません。

- `POST /couponStatus`
- `POST /detectReplace`
- `DELETE /token`
- `GET /frontToken`

調査完了後は Frida セッションを終了し、端末に token やレスポンスを転送しないでください。

## GAPI 実装検証

`capture_authorization.py` は、起動中の公式アプリが送信した Bearer ヘッダーを標準出力へ表示せず、
指定したファイルへ mode `0600` で保存します。出力先は必ずリポジトリ外の一時パスにしてください。

```sh
python3 Tools/frida/capture_authorization.py \
  --output /tmp/myiijmio-authorization \
  --timeout 60
```

取得待ちになった場合は、公式アプリの「データ量」画面で更新を1回行います。出力ファイルはcurlの
header-file形式なので、tokenをプロセス引数へ載せずに使用できます。

```sh
curl -H @/tmp/myiijmio-authorization \
  -H 'Accept: application/json' \
  https://gapi.iijmio.jp/lineInfo
```

`validate_gapi_responses.swift` は保存済みJSONをアプリ本体と同じGAPI型でデコードし、
`AggregatePayload` への変換とCodable round-tripを検証します。匿名化fixtureは
`Tests/Fixtures/GAPI/` にあります。

`validate_gapi_live.swift` は一時Authorizationファイルを読み、`MyIIJmioAPIClient` 自身で
GAPIを取得します。`MyIIJmioAPIClient(debugResponsesEnabled: false)` を使うため、実レスポンスを
DebugResponseStoreへ保存しません。`--expect-auth-failure` では無効tokenが認証エラーとして処理されることを確認できます。

`validate_gapi_login.swift` は標準入力の1行目からmioID、2行目からパスワードを読み、`POST /token`、
主要GAPIの取得、`AggregatePayload`への変換、Codable round-tripを実アカウントでE2E検証します。
資格情報をコマンドライン引数へ渡さず、成功時も件数だけを出力します。実行ファイルはリポジトリ外へ
コンパイルし、入力履歴を残さない端末から実行してください。

検証終了後は、Authorizationファイル、実レスポンス、検証バイナリを削除してください。
