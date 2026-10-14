import AppIntents
import WidgetKit

struct GetDataIntent: AppIntent {
    static var title: LocalizedStringResource { "データを取得" }
    static var description: IntentDescription {
        IntentDescription("IIJmioの最新データを取得し、残量・使用量・契約・請求情報をJSONテキストで返します。「入力から辞書を取得」で各項目を利用できます。ログインが必要です。使いすぎ通知はアラート設定に従います。")
    }
    static var openAppWhenRun: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let outcome = try await WidgetRefreshService().refreshForWidget(forceGAPIUpdate: true)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
            guard let json = DebugPrettyFormatter.prettyJSONString(outcome.payload) else {
                throw CocoaError(.coderInvalidValue)
            }
            RefreshLogStore().append(trigger: .shortcut, result: .success)
            return .result(value: json)
        } catch {
            RefreshLogStore().append(trigger: .shortcut, result: .failure,
                                     errorDescription: error.localizedDescription)
            throw error
        }
    }
}
