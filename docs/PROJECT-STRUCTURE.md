# IIJWidget プロジェクト構造まとめ

## 概要
IIJWidget は、IIJ（Internet Initiative Japan）の残データ量、請求額などの情報を表示する iOS/macOS 用 SwiftUI アプリケーションです。WidgetKit 拡張機能（`RemainingDataWidget`）を備え、メインタグゲット（`IIJWidget`）と共有コードを使用したマルチターゲット Xcode プロジェクト構造です。アプリはタブベースのナビゲーション（ホーム、利用状況、請求、設定）、使用量/請求のチャート、利用アラート（グラフ強調）、セキュアな認証情報保存を備えています。データは API クライアントで取得し、パースして App Groups でウィジェットと共有します。

- **主な技術スタック**: SwiftUI（UI）、WidgetKit（ウィジェット）、Combine/Async-Await（データフロー）、App Groups（共有データ）、App Groups 対応の Xcode プロジェクト。
- **高レベルアーキテクチャ**:
  1. **データフロー**: セキュアに認証情報を保存 → IIJAPIClient で生データを取得 → パーサー（DataUsageParser, BillDetailParser）で処理 → モデル（IIJModels, WidgetSharedModels）で構造化 → ViewModel（AppViewModel）で状態管理 → SwiftUI ビューで描画（チャート、タブ、オンboarding）。
  2. **共有レイヤー**: `Shared/` にコアロジック（API、パース、ストレージ、アラート）を配置し、AppGroup.swift と AggregatePayloadStore.swift でアプリ-ウィジェット同期。
  3. **ウィジェット更新**: WidgetRefreshService.swift、RefreshWidgetIntent.swift、TimelineProvider（RemainingDataWidget.swift）でバックグラウンド更新。
  4. **最近の機能**（コミットから）：アニメーション付きチャート（UsageChartCards.swift）、しきい値強調（使いすぎアラート）、ゼロデータ処理、非正クーポン fallback。
- **ビルド/デプロイ**: GitHub Actions で PR 配布（Firebase）と TestFlight リリース。VSCode 統合（.vscode/launch.json）。

## ディレクトリ構造
```
Users/yyyywaiwai/IIJWidget/
├── .github/                    # CI/CD ワークフロー（PR 配布、TestFlight リリース）
│   └── workflows/
├── .vscode/                    # VSCode 起動設定
├── docs/                       # プロジェクトドキュメント（IIJ エンドポイント、ContentView リファクタ仕様）
├── IIJWidget/                  # メインタグ（SwiftUI アプリ）
│   ├── Assets.xcassets/        # アプリアイコン、アクセントカラー
│   ├── Model/                  # アプリ固有モデル
│   ├── ViewModel/              # アプリ状態管理
│   ├── Views/                  # SwiftUI ビュー（タブ、コンポーネント、チャート）
│   ├── IIJWidget.entitlements  # App Group エンティトルメント
│   ├── IIJWidgetApp.swift      # アプリエントリポイント（@main）
│   └── ContentView.swift       # ルートビュー
├── IIJWidget.xcodeproj/        # Xcode プロジェクト（ターゲット: IIJWidget, RemainingDataWidget）
│   ├── project.pbxproj
│   ├── xcuserdata/
│   └── xcshareddata/xcschemes/ # ビルドスキーム
├── RemainingDataWidget/        # WidgetKit 拡張ターゲット
│   ├── RemainingDataWidget.entitlements
│   ├── RemainingDataWidget.swift # ウィジェットエントリ（TimelineProvider）
│   ├── RemainingDataWidgetBundle.swift
│   ├── ConfigurationAppIntent.swift
│   ├── RefreshWidgetIntent.swift
│   └── WidgetExtensionInfo.plist
├── Shared/                     # 共有フレームワーク/コード（アプリ + ウィジェット）
│   ├── Helpers/
│   ├── IIJAPIClient.swift      # API ネットワーキング
│   ├── IIJModels.swift         # コアデータモデル
│   ├── CredentialStore.swift   # セキュア認証情報（App Groups）
│   ├── DataUsageParser.swift
│   ├── BillDetailParser.swift
│   ├── ChartDataBuilder.swift  # チャート準備
│   ├── WidgetRefreshService.swift
│   ├── AggregatePayloadStore.swift
│   ├── AppGroup.swift
│   └── WidgetSharedModels.swift
└── Tools/                      # スタンドアロンスイフトツール（アプリ外）
    └── IIJFetcher/             # データ取得/パース用 SPM パッケージ
        ├── Sources/IIJFetcher/
        ├── Package.swift
        └── README.md
├── .gitignore
├── AGENTS.md
├── LICENSE
├── README.md
└── build.log
```

## 主なディレクトリと用途
- **IIJWidget/**: コア iOS/macOS アプリソース。機能別ビュー（タブ: HomeDashboardTab.swift, UsageListTab.swift, BillingTabView.swift, SettingsTab.swift）、コンポーネント（チャート、プレースホルダー、オーバーレイ）、オンboarding、アプリ固有モデル/ViewModel を含む。
- **RemainingDataWidget/**: ウィジェット拡張。WidgetKit タイムライン、設定/更新インテント、バUNDLE エントリポイントを実装。App Groups でデータ共有。
- **Shared/**: クロスターゲットモジュール。ビジネスロジック（API クライアント、パーサー、モデル、ストレージ、チャートビルダー、アラートチェッカー、ウィジェットサービス）を格納。アプリ-ウィジェット同期の要。
- **IIJWidget.xcodeproj/**: Xcode プロジェクトファイル。2つのスキーム（アプリ + ウィジェット）、ユーザー データ、ワークスペースを定義。共有コンテナ用 App Groups をサポート。
- **Tools/IIJFetcher/**: データ取得/パーステスト用独立 SPM ツール（Shared パーサーと一部重複）。アプリビルド外。
- **.github/workflows/**: GitHub Actions で自動ビルド/配布。
- **docs/**: API エンドポイント仕様とリファクタノート。
- **Assets.xcassets/**: アプリアイコン（1024x1024 PNG）、アクセントカラー。

## 主要ファイル
### エントリポイント
- `/Users/yyyywaiwai/IIJWidget/IIJWidget/IIJWidgetApp.swift`: `@main` SwiftUI アプリライフサイクル、`MainTabView` をルートに設定。
- `/Users/yyyywaiwai/IIJWidget/RemainingDataWidget/RemainingDataWidget.swift`: ウィジェットタイムラインプロバイダ。
- `/Users/yyyywaiwai/IIJWidget/IIJWidget/ContentView.swift`: 初期コンテンツ（オンboarding リダイレクト？）。

### 設定 & Xcode 固有
- `/Users/yyyywaiwai/IIJWidget/IIJWidget.xcodeproj/project.pbxproj`: プロジェクトブループリント（ターゲット、ビルドフェーズ、エンティトルメント）。
- `/Users/yyyywaiwai/IIJWidget/IIJWidget/IIJWidget.entitlements`: App Groups（共有コンテナ）。
- `/Users/yyyywaiwai/IIJWidget/RemainingDataWidget/RemainingDataWidget.entitlements`: ウィジェット エンティトルメント。
- `/Users/yyyywaiwai/IIJWidget/Assets.xcassets/Contents.json`: アセットカタログ。

### モデル
- `/Users/yyyywaiwai/IIJWidget/Shared/IIJModels.swift`: IIJ データ構造体（利用状況、請求）。
- `/Users/yyyywaiwai/IIJWidget/Shared/WidgetSharedModels.swift`: ウィジェットペイロード。
- `/Users/yyyywaiwai/IIJWidget/IIJWidget/Model/AppSection.swift`: アプリ UI セクション。
- `/Users/yyyywaiwai/IIJWidget/IIJWidget/Model/CredentialsField.swift`: 認証情報 UI フィールド。

### サービス & パーサー
- `/Users/yyyywaiwai/IIJWidget/Shared/IIJAPIClient.swift`: IIJ エンドポイント用 HTTP クライアント。
- `/Users/yyyywaiwai/IIJWidget/Shared/DataUsageParser.swift`: 利用状況パース。
- `/Users/yyyywaiwai/IIJWidget/Shared/BillDetailParser.swift`: 請求詳細パース。
- `/Users/yyyywaiwai/IIJWidget/Shared/CredentialStore.swift`: セキュアストレージ。
- `/Users/yyyywaiwai/IIJWidget/Shared/WidgetRefreshService.swift`: バックグラウンド更新。

### UI コンポーネント（SwiftUI）
- **ルート/タブ**: `/Users/yyyywaiwai/IIJWidget/IIJWidget/Views/Root/MainTabView.swift`。
- **ホーム**: `/Users/yyyywaiwai/IIJWidget/IIJWidget/Views/Tabs/Home/HomeDashboardTab.swift`。
- **利用状況**: `/Users/yyyywaiwai/IIJWidget/IIJWidget/Views/Tabs/Usage/UsageListTab.swift`。
- **請求**: `/Users/yyyywaiwai/IIJWidget/IIJWidget/Views/Tabs/Billing/BillingTabView.swift`。
- **設定**: `/Users/yyyywaiwai/IIJWidget/IIJWidget/Views/Tabs/Settings/SettingsTab.swift`。
- **チャート**: `/Users/yyyywaiwai/IIJWidget/IIJWidget/Views/Components/Charts/UsageChartCards.swift`、`ChartCallout.swift`、`ChartPlaceholder.swift`。
- **共通**: `/Users/yyyywaiwai/IIJWidget/IIJWidget/Views/Components/Common/DashboardCard.swift`、`Placeholders.swift`。
- **その他**: `/Users/yyyywaiwai/IIJWidget/IIJWidget/Views/Components/Feedback/FeedbackOverlays.swift`、`/Users/yyyywaiwai/IIJWidget/IIJWidget/Views/Onboarding/OnboardingViews.swift`。

### ViewModel
- `/Users/yyyywaiwai/IIJWidget/IIJWidget/ViewModel/AppViewModel.swift`: 中央アプリ状態（データ、認証情報の Observable）。

## コアモジュール（最近のコミットに基づく）
- **モデル**: IIJModels.swift（利用/請求構造体、ゼロデータ処理）。
- **サービス**: IIJAPIClient.swift、パーサー（非正クーポン fallback）。
- **UI**: タブビュー、DashboardCard.swift（タブレットアライメント）。
- **チャート**: UsageChartCards.swift（アニメーション付きチャート）。
- **使いすぎアラート**: UsageChartCards.swift / UsageListTab.swift（しきい値超過時の強調表示）。

追跡ファイル総数: 約50（主に Swift）。Node.js/package.json なし、純粋ネイティブ Swift/iOS。Git リポジトリは `main` ブランチ、最近の修正/機能追加。
