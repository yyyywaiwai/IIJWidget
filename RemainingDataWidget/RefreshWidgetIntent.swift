import AppIntents
import WidgetKit

@available(iOSApplicationExtension 17.0, *)
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource { "データ更新" }

    func perform() async throws -> some IntentResult {
        do {
            _ = try await WidgetRefreshService().refresh()
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
            return .result(dialog: IntentDialog("最新の情報を取得しました"))
        } catch WidgetRefreshError.missingCredentials {
            return .result(dialog: IntentDialog("アプリで資格情報を入力してください"))
        }
    }
}
