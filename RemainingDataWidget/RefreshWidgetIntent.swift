import AppIntents
import WidgetKit

@available(iOSApplicationExtension 17.0, *)
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource { "データ更新" }
    private let refreshService = WidgetRefreshService()
    private let dataStore = WidgetDataStore()
    private let logStore = RefreshLogStore()
    private let displayPreferenceStore = DisplayPreferencesStore()

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await updateRefreshingState(true)
        defer {
            Task { await updateRefreshingState(false) }
        }

        let preferences = displayPreferenceStore.load()
        do {
            // 成功フラグをリセットしてから開始
            dataStore.setSuccessUntil(nil)
            _ = dataStore.setRefreshingState(true)
            await MainActor.run {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
            }

            let outcome = try await refreshService.refreshForWidget(calculateTodayFromRemaining: preferences.calculateTodayFromRemaining)
            
            // Check usage alerts after successful refresh
            await UsageAlertChecker().checkUsageAlerts(payload: outcome.payload)
            
            await MainActor.run {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
            }
            logStore.append(trigger: .widgetManual, result: .success)
            return .result(dialog: IntentDialog("最新の情報を取得しました"))
        } catch WidgetRefreshError.missingCredentials {
            logStore.append(
                trigger: .widgetManual,
                result: .failure,
                errorDescription: WidgetRefreshError.missingCredentials.localizedDescription
            )
            return .result(dialog: IntentDialog("アプリで資格情報を入力してください"))
        } catch {
            logStore.append(
                trigger: .widgetManual,
                result: .failure,
                errorDescription: error.localizedDescription
            )
            return .result(dialog: IntentDialog("更新に失敗しました: \(error.localizedDescription)"))
        }
    }

    private func updateRefreshingState(_ isRefreshing: Bool) async {
        if isRefreshing {
            dataStore.setSuccessUntil(nil)
        }
        _ = dataStore.setRefreshingState(isRefreshing)
        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
        }
    }
}
