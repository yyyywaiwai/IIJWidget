# IIJWidgetの取得方式

## 現行構成

残量・契約・請求・月次・直近の日次はGAPI専用。通信方式の選択、旧APIへのフォールバック、
旧キャッシュのデコード互換は存在しない。会員サイトの利用は**30日履歴の表だけ**に限定する。

更新ボタン・引っ張って更新・アプリ自動更新・Widgetの更新はGAPIのみ。
30日表は利用量タブを開くたびに別途取得する。実行中のGAPI更新があれば、その完了を待ってから取得する。
月別/日別の切り替えや、利用量タブ内の更新操作では表を取り直さない。

| 取得対象 | クライアント / API |
| --- | --- |
| 認証・残量・回線 | `MyIIJmioAPIClient`: `/token`, `/lineInfo`, `/dataTraffic` |
| 契約・請求明細 | GAPI `/contract`, `/usageFee` |
| 月次・当月の日次 | GAPI `/pastDataTraffic`（回線ごと） |
| 直近7日・当日実測 | GAPI `/dataTraffic` の `lastSevenDaysDataList` |
| 過去30日の履歴 | `ThirtyDayUsageClient`: `/auth/login/`, `/api/member/login`, `/service/setup/hdc/viewdailydata/` のGET/POSTのみ |

30日取得のGETはフォームとCSRF取得用で、プレビュー値は使わない。POST表を解析し、GAPI回線IDへ
一意に照合してから日付を正規化する。重複日の高速値はGAPIを優先し、欠損した低速値は30日表で補完する。
日別が取得できない場合、残量からの推定値は作らない。

GAPIは保存tokenを使用し、401/403のみ資格情報で再ログインする。通信エラー・505・デコード失敗は
そのまま失敗とし、30日側の認証や取得へ切り替えない。30日側のCookie失効も独立して再ログインする。
30日取得や回線照合が失敗した場合は既存の表・GAPIキャッシュを保持し、取得済みのGAPI更新は取り消さない。

## 保存モデル

- `TrafficSummary.ServiceInfo.id` / 利用量の`lineID`: GAPIの`lineServiceCode`。契約コードだけでSIMをまとめない。
- 残量・容量はGBの数値。クーポンの`sequenceNo`や旧`couponData`は持たない。
- 月次GB / 日次MBは数値で保存し、表示文字列は計算プロパティ。日付を統一して重複日を排除する。
- 請求詳細は`/usageFee`から変換して`billDetails`に保存。詳細を開くたびの再通信を省く。
- `gapi.payload.v2`と`gapi.widget.snapshot.v2`のみ読み書き。旧形式からの移行はしない。
- `dailyUsage`はGAPI日次、`thirtyDayUsage`は取得済みの30日表。表示用の`dailyUsageWithHistory`で統合し、通常更新では表を保持する。回線がなくなった場合は対応する表を破棄する。
- `historyFetchedAt`はGAPI月次・契約・請求の取得日時。Widgetでは同日のGAPI履歴を再利用し、30日表の取得ではGAPIの更新日時を変えない。
- 手入力で認証し直す際とログアウト時はtoken / Cookie / キャッシュを破棄し、別アカウントのデータ混在を防ぐ。

## 検証

`Tools/IIJFetcher`が本体の共有ソースを直接使用する。`swift test`は匿名化fixtureの検証、
`swift run IIJFetcher`は標準入力の資格情報を使ったGAPI + 30日表の実通信検証。
資格情報・token・レスポンス本文をCLIから保存・出力しない。

## 過去のGAPI調査記録

以下は2026-08-06の観測記録であり、現行実装では上記取得経路だけを使用する。

## MyIIJmio 公式アプリの GAPI

2026-08-06 に、USB 接続した iPhone 上の MyIIJmio 3.2.5
（bundle identifier: `jp.ad.iij.my-iijmio`）を Frida で観測した。公式アプリは
React Native / Axios / `RCTHTTPRequestHandler` を使用し、会員サイトの Cookie API とは別の
`https://gapi.iijmio.jp` を利用している。

調査時のログは URL クエリ値、`Authorization`、Cookie、リクエスト本文の実値、レスポンス値を
マスクし、フィールド名と型のみを記録した。状態を変更する API は静的解析だけに留め、実行していない。

### 認証

ログインは会員サイト Cookie を作る方式ではなく、次の token API を直接利用する。

```http
POST https://gapi.iijmio.jp/token
Accept: application/json
Content-Type: application/json
Cache-Control: no-store
Authorization: appVersion=3.2.5
timeout: 45000

{
  "loginId": "<mioID またはメールアドレス>",
  "password": "<password>"
}
```

公式アプリの bundle では、成功レスポンスから `mioId`、`token`、`contractorName` を取り出している。
以降の GAPI リクエストは次のヘッダー形式を使う。

```http
Authorization: Bearer <token>,appVersion=3.2.5
Accept: application/json
Content-Type: application/json
charset: utf-8
Cache-Control: no-store
timeout: 45000
```

手動更新など、キャッシュを避ける呼び出しでは `ForceUpdate: 1` が追加される。実際の通信では
HTTP ヘッダー名が小文字化される場合があるため、クライアント側では大文字・小文字を区別しないこと。

ログアウトは `DELETE /token`。公式アプリは token を React Native の `auth` ストレージへ保存しているが、
IIJWidget へ採用する場合は App Group 対応 Keychain に保存し、UserDefaults や平文ファイルには保存しない。

### 実通信で確認した読み取り API

以下は同一の認証済みセッションで HTTP 200 を確認した。表中のレスポンスは個人値を除いた構造だけを示す。

| エンドポイント | メソッド / パラメータ | 主なレスポンス構造 | 用途 |
| --- | --- | --- | --- |
| `/identityStatus` | GET。通常 `ForceUpdate: 1` | `code`, `IdentityStatus[{ Contractor, DoryStatus }]` | 契約者状態・メンテナンス系状態の確認 |
| `/lineInfo` | GET。初期取得時 `ForceUpdate: 1` | `mioId`, `statusCode`, `lineInfo.hdcList[]`, `lineInfo.hddList[]`。各回線に `serviceCode`, `lineServiceCode`, `planName`, `telNo` など | 回線選択と API パラメータ組み立て |
| `/contract` | GET。公式アプリは `mainLineServiceCode: null` を渡すが Axios により省略される | `contract.hdcList[]`, `contract.hddList[]`。`applicationDate`, `chargePlan`, `eSim`, `serviceStatus`, `startDate` など | 契約一覧 |
| `/usageFee` | GET | `billingMonth`, `billingPeriod`, `billingTotalAmount`, `billingSummary[]`。明細は `detailDataList[].detailItemList[]` | 直近の請求と内訳 |
| `/dataTraffic` | GET。トップは `dataDetailFlag=0`、詳細は `dataDetailFlag=1`。必要に応じて `serviceCode`, `lineServiceCode`, `mainLineServiceCode` | `dataTraffic.hdcList[]`, `hddList[]`, `mainHdd[]`, `pullDownNameList[]` | 残量、当月利用量、直近 7 日、高速通信状態 |
| `/pastDataTraffic` | GET。`serviceCode` と、回線種別に応じて `lineServiceCode` | `lastFiveMonthInfo[]`, `thisMonthDailyInfo[]`, `thisMonthInfo`, 各 data unit | 月別 5 か月と当月日別利用量 |

実測した `/dataTraffic` の主な回線要素は次の構造だった。

```text
dataTraffic.hdcList[]
  serviceCode / lineServiceCode / groupServiceCode
  planName / telNo / msIsdn / startDate
  couponValue / expireList[]
  regulation / 5g
  thisMonthDataList
    availableDataTraffic / availableDataTrafficUnit
    maxDataTraffic / maxDataTrafficUnit
    couponStatus / regulationStatus
    chargeAlert / chargeAlertThreshold
    dataShare / fiveG / thisMonth / usePeriod
  lastSevenDaysDataList
    lastSevenDays
    lastSevenDaysDataHighUnit / lastSevenDaysDataLowUnit
    dailyDataList[] { month, date, dayOfWeek, high, low }
```

`dataDetailFlag=0` でも残量と当月情報を取得できる。直近 7 日の `lastSevenDaysDataList` は、
公式アプリの通常トップ画面通信では返っており、読み取り専用 probe の同フラグ呼び出しでは省略される場合があった。
手動更新時の `ForceUpdate: 1`、サーバーキャッシュ、レスポンス生成タイミングのいずれかが影響している可能性があるため、
クライアントモデルでは optional として扱う。

### 静的解析で確認した補助・更新 API

| エンドポイント | メソッド | リクエスト / 用途 | 調査時の扱い |
| --- | --- | --- | --- |
| `/couponStatus` | POST | `{ serviceCode, lineServiceCode, couponStatus }`。高速通信 ON/OFF を切り替える | 状態変更のため未実行 |
| `/detectReplace` | POST | `{ mioId, invalidMioId, api }`。レスポンスの mioID 不一致検出時に送信 | 通常取得には不要。未実行 |
| `/frontToken` | GET | 認証済み Bearer で Web 遷移用の一時 `token` を取得 | 未実行 |
| `/mio-announce` | GET | 認証なしのお知らせ JSON | bundle から確認 |

`/frontToken` の結果は、次のように会員サイト内の画面へシングルサインオンするために使われる。

```text
https://www.iijmio.jp/mobileappauth/signOn
  ?token=<frontToken>
  &nextUrl=<遷移先>
  [&serviceCode=<serviceCode>]
  &webView=<true|false>
```

GAPI 共通クライアントは 400、401、403、404、429、500、502、503、505、598 を個別処理している。
特に 505 は公式アプリの強制更新要求として扱われる。`appVersion` は認証契約の一部なので、3.2.5 の固定値は
将来無効になる可能性がある。バージョン値は一か所に集約し、505では更新要求を表示する。旧方式へは切り替えない。
