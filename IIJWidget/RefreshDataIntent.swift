import AppIntents
import WidgetKit

struct RefreshDataIntent: AppIntent {
    static var title: LocalizedStringResource { "データを更新して使いすぎを確認" }
    static var description: IntentDescription {
        IntentDescription("IIJmioの最新データを取得し、設定した使用量を超えていれば通知します。事前にアプリでログインと通知の許可を行ってください。")
    }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            _ = try await WidgetRefreshService().refreshForWidget(forceGAPIUpdate: true)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
            RefreshLogStore().append(trigger: .shortcut, result: .success)
            return .result(dialog: "最新のデータを取得しました。通知はアラート設定と通知許可に従います。")
        } catch {
            RefreshLogStore().append(trigger: .shortcut, result: .failure,
                                     errorDescription: error.localizedDescription)
            throw error
        }
    }
}

struct MioWidgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RefreshDataIntent(),
                    phrases: ["\(.applicationName)のデータを更新"],
                    shortTitle: "データ更新と使いすぎ確認",
                    systemImageName: "arrow.clockwise")
        AppShortcut(intent: GetDataIntent(),
                    phrases: ["\(.applicationName)のデータを取得"],
                    shortTitle: "データを取得",
                    systemImageName: "chart.bar.doc.horizontal")
    }
}
