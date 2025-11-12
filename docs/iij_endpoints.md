# IIJmio 会員サイト API サマリ

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
| `/api/front/getChatBotPopupToken` | GET | なし | `{ "token": "…", "popupSrc": "…" }` | 画面右下のカラクリチャット呼び出し用トークン。ウィジェットでは不要。 | `chatbot.RO5WKR_d.js` |
| `/service/setup/hdc/viewmonthlydata/` | HTML (POST で CSRF 更新) | `hdoCode`, `_csrf` を含む form POST | `<table>` 形式で月別の高速/低速利用量 | 純粋な HTML 画面。API エンドポイントは存在せず、スクレイピングかヘッドレスブラウザでの取得が必要。 | 画面本体 |
| `/service/setup/hdc/viewdailydata/` | HTML (GET + POST) | GET: 画面ロード。POST: `hdoCode`, `_csrf` | GET の `<div class="viewdata">` は直近 4 日分、POST の `<table>` は過去 30 日分 | 4 日プレビューに当日分が含まれる一方、POST 側は更新遅延で当日が欠落するケースがあるため、GET プレビューで得た行を `hdoCode` ごとにマージして利用する。 | 画面本体 / `DataUsageHTMLParser.previewDailyServices` |

> **注記**
> - 各 API は `https://www.iijmio.jp` 配下で提供され、セッションは Cookie ベース (JSESSIONID 等) です。
> - `error` フィールドを含むレスポンスは全画面共通のエラーハンドラで扱われるため、クライアント側でも捕捉しておくと原因特定が容易になります。
> - バンドル名は 2025-11-09 時点のもので、リリースにより変更される可能性があります。
