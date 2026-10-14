import AppIntents
import WidgetKit

@available(iOSApplicationExtension 17.0, *)
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource { "データ更新" }
    private let dataStore = WidgetDataStore()
    private let logStore = RefreshLogStore()

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await updateRefreshingState(true)
        let dialog: IntentDialog
        do {
            _ = try await WidgetRefreshService().refreshForWidget(forceGAPIUpdate: true)
            logStore.append(trigger: .widgetManual, result: .success)
            dialog = IntentDialog("最新の情報を取得しました")
        } catch WidgetRefreshError.missingCredentials {
            logStore.append(
                trigger: .widgetManual,
                result: .failure,
                errorDescription: WidgetRefreshError.missingCredentials.localizedDescription
            )
            dialog = IntentDialog("アプリで資格情報を入力してください")
        } catch {
            logStore.append(
                trigger: .widgetManual,
                result: .failure,
                errorDescription: error.localizedDescription
            )
            dialog = IntentDialog("更新に失敗しました: \(error.localizedDescription)")
        }
        // 終了処理を非構造化 Task に逃さず、成功・失敗とも状態を保存してから応答する。
        await updateRefreshingState(false)
        return .result(dialog: dialog)
    }

    private func updateRefreshingState(_ isRefreshing: Bool) async {
        if isRefreshing {
            dataStore.setSuccessUntil(nil)
        }
        dataStore.setRefreshingState(isRefreshing)
        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
        }
    }
}
