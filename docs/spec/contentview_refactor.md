# ContentView リファクタリングチェックリスト

## 背景
- [x] ContentView がタブ構成、オンボーディング表示、シーンフェーズ監視、フォーカス状態管理など UI ルート全般を単一ファイルで担っている。
- [x] 同一ファイルに Home/Usage/Billing/Settings 各タブの複雑な UI とビジネスロジックが集約され、AppViewModel への依存が高くなっている。
- [x] オンボーディング画面群やチャート系ロジック、共通 UI コンポーネントも ContentView.swift に内包され、再利用性とテスト容易性が阻害されている。

## 対応方針
- [x] ContentView からタブ構造とグローバル UI 制御のみを残し、`MainTabView`（仮称）など別 View へ委譲する。
- [x] Field/AppSection などルート固有の型を専用ファイルへ移し、状態管理の責務境界を明示する。
- [x] Home/Usage/Billing/Settings 各タブを `IIJWidget/Views/Tabs/<TabName>/` 相当のファイルへ分割し、必要なら個別 ViewModel を導入する。
- [x] 設定タブで扱う資格情報フォーム／データ取得アクション／ログアウト確認を独立した小ビューに分解し、フォーカス管理をローカルに閉じ込める。
- [x] オンボーディングフローを `Onboarding/` モジュールに切り出し、ContentView からは表示トリガーと完了ハンドラのみを扱う。
- [x] `MonthlyUsageChartCard` などチャート UI と `UsageChartPoint` 生成ロジックを `Components/Charts` や `Shared/Services/ChartDataBuilder` に移して整理する。
- [x] `EmptyStateView` や `StateFeedbackBanner` など汎用ビューを `Shared/Components` に配置し、アプリ全体で再利用可能にする。
- [x] 日付・数値ラベル生成系のユーティリティを専用 Formatter/Helper へ分離し、View から純粋ロジックを排除する。
- [x] `IIJWidgetApp` が参照するエントリーポイントを新しいルートビューに更新し、動作確認として `xcodebuild -scheme IIJWidget -configuration Debug` を実行する。（2025-11-16 Debug ビルド成功）
