import AppIntents
import WidgetKit

@available(iOSApplicationExtension 17.0, *)
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource { "データ更新" }
    private let refreshService = WidgetRefreshService()
    private let dataStore = WidgetDataStore()

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await updateRefreshingState(true)
        defer {
            Task { await updateRefreshingState(false) }
        }

        do {
            _ = try await refreshService.refresh(
                manualCredentials: nil,
                persistManualCredentials: false,
                allowSessionReuse: true,
                allowKeychainFallback: true
            )
            await MainActor.run {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
            }
            return .result(dialog: IntentDialog("最新の情報を取得しました"))
        } catch WidgetRefreshError.missingCredentials {
            return .result(dialog: IntentDialog("アプリで資格情報を入力してください"))
        } catch {
            return .result(dialog: IntentDialog("更新に失敗しました: \(error.localizedDescription)"))
        }
    }

    private func updateRefreshingState(_ isRefreshing: Bool) async {
        guard dataStore.setRefreshingState(isRefreshing) else { return }
        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
        }
    }
}
