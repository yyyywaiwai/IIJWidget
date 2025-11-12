# IIJFetcher CLI

IIJFetcher は IIJmio 会員サイトの非公開 API を直接叩き、通信量・請求情報・回線状態・月別/日別利用量を JSON で取得するための検証用 CLI です。ログイン後に以下のモードを選べます。

- `--mode top` : `/api/member/top`（残量カードやクーポン情報）
- `--mode bill` : `/api/member/getBillSummary`（最大 7 ヶ月分の請求サマリ）
- `--mode status` : `/api/member/getServiceStatus`（各回線の稼働状態）
- `--mode usage` : `/service/setup/hdc/viewmonthlydata/`（回線別の月別データ利用量テーブル）
- `--mode daily` : `/service/setup/hdc/viewdailydata/`（直近 30 日の利用量と日別サマリ）
- `--mode all` : 上記すべてを 1 つの `AggregatePayload`（`{"fetchedAt","top","bill","serviceStatus","monthlyUsage","dailyUsage"}`）にまとめて出力

## 前提

- Swift 6.2 以降 (Xcode 16 以降) — `Package.swift` の `swift-tools-version` に合わせてください
- インターネット接続
- IIJmio の mioID もしくは登録メールアドレスとパスワード

## 使い方

1. 環境変数で資格情報を渡すか、コマンドライン引数で指定します。

```bash
export IIJ_MIO_ID="mainaddress@example.com"
export IIJ_PASSWORD="password"
```

2. 任意のモードでフェッチを実行します（デフォルトは `top`）。

```bash
cd Tools/IIJFetcher
swift run IIJFetcher --mode top
swift run IIJFetcher --mode bill
swift run IIJFetcher --mode status
swift run IIJFetcher --mode usage
swift run IIJFetcher --mode daily
swift run IIJFetcher --mode all --mio-id mail@example.com --password pass
```

3. 成功するとそれぞれの API レスポンスがそのまま整形済み JSON で標準出力に流れます。

`--mode top` の例:

```json
{
  "hasVouchers" : false,
  "prefixList" : ["hdc","hdu"],
  "serviceInfoList" : [
    {
      "planName" : "ギガプラン",
      "serviceName" : "音声SIM",
      "totalCapacity" : 10,
      "couponData" : [
        { "month" : "202512", "couponValue" : 6.83 }
      ]
    }
  ],
  "usagePeriod" : "9ヵ月"
}
```

`--mode bill` の例:

```json
{
  "billList" : [
    { "month" : "202509", "totalAmount" : 904, "isUnpaid" : false },
    { "month" : "202508", "totalAmount" : 904, "isUnpaid" : false }
  ],
  "isVoiceSim" : true,
  "isImt" : false
}
```

`--mode status` の例:

```json
{
  "jmbNumberChangePossible" : false,
  "serviceInfoList" : [
    {
      "planCode" : "CN1000",
      "serviceCodePrefix" : "hdc",
      "status" : "O",
      "simInfoList" : [ { "simType" : "2", "status" : "O" } ]
    }
  ]
}
```

`--mode usage` は HTML テーブルをパースして以下のような JSON を返します。

```json
[
  {
    "hdoCode": "hdc00000000",
    "planName": "ギガプラン",
    "entries": [
      { "month": "202509", "inGB": 8.4, "outGB": 7.9 }
    ]
  }
]
```

`--mode daily` は直近 30 日のサマリを次のような JSON で返します。

```json
[
  {
    "hdoCode": "hdc00000000",
    "entries": [
      { "date": "2025-09-08", "usedGB": 0.42 }
    ]
  }
]
```

`--mode all` では `{"fetchedAt": ..., "top": ..., "bill": ..., "serviceStatus": ..., "monthlyUsage": [...], "dailyUsage": [...]}` という 1 つの JSON にまとまり、Swift アプリの `AggregatePayload` と互換です。

失敗した場合は API 側のエラーコード（例: `ERROR_CODE_008`）もしくは HTTP ステータスを表示して終了します。

## 実装メモ

- ログインは `/api/member/login` に JSON で `mioId` / `password` を POST し、HttpOnly Cookie を取得します。
- `URLSessionConfiguration.ephemeral`＋専用 Cookie ストアを使っているため、ブラウザセッションとは独立しています。
- `usage`/`daily` モードは `viewmonthlydata` / `viewdailydata` のフォームをクロールし、`DataUsageHTMLParser` でテーブルを `MonthlyUsageService` / `DailyUsageService` モデルへ変換します。
- `--mode all` の出力はアプリ/ウィジェットと同じ `AggregatePayload` をそのまま JSON 化したものです。
- 詳細な API 一覧は `docs/iij_endpoints.md` を参照してください。
