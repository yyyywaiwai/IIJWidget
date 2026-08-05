# IIJmio 会員サイト API サマリ

## 通信方式の選択

アプリの「設定」→「通信方式」で、次回更新に利用する方式を選択できる。

- **新形式（MyIIJmioアプリ方式）**: `gapi.iijmio.jp` を本家MyIIJmioアプリと同じ認証・API形式で利用する。
- **従来方式（会員サイト）**: 会員サイトのセッションCookieを利用する。

選択値はApp GroupのUserDefaultsへ保存され、アプリ本体とウィジェットで共有される。選択した方式が失敗しても、もう一方の方式へ自動フォールバックはしない。

Chrome DevTools で取得した Nuxt バンドル（`/_nuxt/*.js`）と実際の通信結果を突き合わせ、会員トップ画面および関連メニューで利用されている代表的な `/api/*` エンドポイントを整理しました。ウィジェットや CLI から参照すべきデータソース選定の参考になります。

| エンドポイント | メソッド | 期待リクエスト例 | 主なレスポンス項目 | 用途 / 備考 | 参照スクリプト |
| --- | --- | --- | --- | --- | --- |
| `/api/member/login` | POST | `{ "mioId": "<ID>", "password": "<PW>" }` | `{}` または `{ "error": "ERROR_CODE_xxx" }` | ログイン本体。実際には事前に `/auth/login/` を GET して WAF 用 Cookie を取得する必要がある。 | `entry.rL2vrYu7.js` |
| `/api/front/loginInfo` | POST | `{}` | `{ "login_flg": true, "user_name": "…", "id_ma": "…", "webViewFlg": false }` | 軽量なログイン状態チェック。初回マウントや WebView 判定に利用。 | `entry.rL2vrYu7.js` |
| `/api/member/getPermissionInfo` | POST | `{}` | `[("ID"), ("hdc"), …]` | 契約単位の権限一覧を取得し、表示可否や遷移ガードに使用。 | `entry.rL2vrYu7.js` |
| `/api/member/getSuspensionInfo` | GET | なし | `{ "unpaidList": [], "suspensionDate": null, … }` | 延滞/利用停止情報取得。返却値が空でも JSON が返る。 | `entry.rL2vrYu7.js` |
| `/api/member/top` | POST | `{}` または `{ "serviceCode": "hdc715…" }` | `serviceInfoList`, `billSummary`, `hasVouchers`, `usagePeriod`, 各種フラグ | 会員トップの主要データ源。`serviceInfoList[*].couponData` にデータ残量クーポンが入る。 | `index._cKtjdew.js` |
| `/api/member/getServiceStatus` | GET | なし | `serviceInfoList[*].simInfoList`, `planCode`, `status`, `jmbNumberChangePossible` | 契約中回線の稼働状態や SIM タイプ一覧。ウィジェットで回線グルーピングする際に利用可。 | `service.xIX5mF4V.js` |
| `/api/member/getBillSummary` | GET | なし | `billList[*].month`, `totalAmount`, `isUnpaid`, `isVoiceSim`, `isImt` | 料金・お支払いタブで表示される直近 7 ヶ月分の請求サマリ。 | `index.9w7tsc_m.js` |
| `/customer/bill/detail/` | POST | `billNoList=111005999429&billNoList=...` | HTML (`bill-detail-top`, `bill-detail-table`, `bill-detail-tax`) | 請求タブの「ご請求明細を確認する」。`billNoList` を複数送ると複数計算書が合算される。 | `common.IV0QDYOx.js` |
| `/api/front/getChatBotPopupToken` | GET | なし | `{ "token": "…", "popupSrc": "…" }` | 画面右下のカラクリチャット呼び出し用トークン。ウィジェットでは不要。 | `chatbot.RO5WKR_d.js` |
| `/service/setup/hdc/viewmonthlydata/` | HTML (POST で CSRF 更新) | `hdoCode`, `_csrf` を含む form POST | `<table>` 形式で月別の高速/低速利用量 | 純粋な HTML 画面。API エンドポイントは存在せず、スクレイピングかヘッドレスブラウザでの取得が必要。 | 画面本体 |
| `/service/setup/hdc/viewdailydata/` | HTML (GET + POST) | GET: 画面ロード。POST: `hdoCode`, `_csrf` | GET の `<div class="viewdata">` は直近 4 日分、POST の `<table>` は過去 30 日分 | 4 日プレビューに当日分が含まれる一方、POST 側は更新遅延で当日が欠落するケースがあるため、GET プレビューで得た行を `hdoCode` ごとにマージして利用する。設定の「当日利用量をデータ残量から計算する」トグルが ON の場合は GET プレビューをスキップし、POST 30 日分のみ取得した上で残量差分から当日分を補完する。 | 画面本体 / `DataUsageHTMLParser.previewDailyServices` |

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
将来無効になる可能性がある。採用時はバージョン値を一か所に集約し、505 を検知したら安全に既存の会員サイト方式へ
フォールバックできる設計にする。

### IIJWidget へ採用する際の差分

現行 `IIJAPIClient` は `https://www.iijmio.jp` の WAF/Cookie セッションを作り、JSON API と HTML
スクレイピングを組み合わせている。GAPI を採用すると、次の置き換えが可能になる。

- `/api/member/login` と Cookie セッションを `/token` と Bearer token に置き換える。
- `/api/member/top` と日次・月次 HTML スクレイピングのデータ量部分を `/dataTraffic` と
  `/pastDataTraffic` に置き換える。
- `/api/member/getBillSummary` と請求 HTML の多くを `/usageFee` に置き換える。
- `/api/member/getServiceStatus` を `/lineInfo` と `/contract` に置き換える。
- widget extension は App Group Keychain の token と、main app が保存した回線選択情報を利用する。
- 401/403 は token 失効、505 は appVersion 失効として区別し、main app での再ログインまたは旧方式への
  フォールバックを行う。

GAPI は公開仕様ではなく、フィールドや認証規則が予告なく変わる可能性がある。初期導入では現行方式を削除せず、
GAPI 優先・会員サイト方式フォールバックとして段階的に移行するのが安全である。

### IIJWidget の実装

`MyIIJmioAPIClient` が `/token`、`/lineInfo`、`/dataTraffic`、`/contract`、`/usageFee`、
`/pastDataTraffic` を担当する。取得結果は `MyIIJmioPayloadMapper` で既存の `AggregatePayload` に変換するため、
アプリ本体とWidgetの表示モデルは従来どおり利用できる。

Bearer tokenは `MyIIJmioTokenStore` により、資格情報とは別のApp Group Keychain項目へ
`kSecAttrAccessibleAfterFirstUnlock` で保存する。ログアウト、認証エラー、公式アプリバージョン不一致ではtokenを削除する。

`WidgetRefreshService` の取得順序は次のとおり。

1. App Group Keychainに保存済みのGAPI token。
2. KeychainのmioID・パスワードでGAPI `/token` に再ログイン。
3. 画面で入力されたmioID・パスワードでGAPI `/token` にログイン。
4. 保存済みの会員サイトCookieセッション。
5. Keychain資格情報を使う従来の会員サイトログイン。
6. 画面入力資格情報を使う従来の会員サイトログイン。

GAPIの401/403では保存tokenを破棄して再ログインへ進む。505、通信エラー、デコードエラーを含むその他の失敗は
tokenや資格情報をログへ出さず、従来方式へフォールバックする。請求詳細も `/usageFee` の `detailDataList` を優先し、
該当明細がない場合だけ既存の請求HTML方式を使う。

> **注記**
> - 各 API は `https://www.iijmio.jp` 配下で提供され、セッションは Cookie ベース (JSESSIONID 等) です。
> - 上記注記は「会員サイト API」に対するもの。MyIIJmio 公式アプリの GAPI は `https://gapi.iijmio.jp` と Bearer token を使う。
> - `error` フィールドを含むレスポンスは全画面共通のエラーハンドラで扱われるため、クライアント側でも捕捉しておくと原因特定が容易になります。
> - バンドル名は 2025-11-09 時点のもので、リリースにより変更される可能性があります。
