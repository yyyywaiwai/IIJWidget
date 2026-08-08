import Combine
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppViewModel: ObservableObject {
    enum LoadState {
        case idle
        case loading(previous: AggregatePayload?)
        case loaded(AggregatePayload)
        case failed(String, lastPayload: AggregatePayload?)
    }

    enum RefreshTrigger {
        case automatic
        case manual
    }

    @Published var mioId: String = ""
    @Published var password: String = ""
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var credentialFieldsHidden = false
    @Published private(set) var lastLoginSource: WidgetRefreshService.LoginSource?
    @Published private(set) var hasStoredCredentials = false
    @Published var accentColors: AccentColorSettings = .default
    @Published var displayPreferences: DisplayPreferences = .default
    @Published var usageAlertSettings: UsageAlertSettings = .default
    @Published private(set) var communicationMethod: CommunicationMethod = .myIIJmioGAPI

    private let credentialStore = CredentialStore()
    private let widgetRefreshService = WidgetRefreshService()
    private let payloadStore = AggregatePayloadStore()
    private let accentColorStore = AccentColorStore()
    private let displayPreferenceStore = DisplayPreferencesStore()
    private let usageAlertStore = UsageAlertStore()
    private let communicationMethodStore = CommunicationMethodStore()
    private let refreshLogStore = RefreshLogStore()

    /// 実行中の更新タスク。SwiftUI の `.refreshable` は自身の Task を
    /// キャンセルすることがあり、構造化された子タスクのまま通信すると
    /// URLSession まで伝播して -999 (キャンセルしました) になる。
    /// ViewModel 側で非構造化 Task として保持し、呼び出し元は完了を待つだけにする。
    private var inFlightRefresh: (trigger: RefreshTrigger, task: Task<Result<Void, Error>, Never>)?
    private var lastAutomaticRefresh: Date?

    init() {
        accentColors = accentColorStore.load()
        displayPreferences = displayPreferenceStore.load()
        usageAlertSettings = usageAlertStore.load()
        communicationMethod = communicationMethodStore.load()

        if let saved = try? credentialStore.load() {
            mioId = saved.mioId
            password = saved.password
            credentialFieldsHidden = true
            hasStoredCredentials = true
        }

        if let cachedPayload = payloadStore.load() {
            state = .loaded(cachedPayload)
        }
    }

    func updateAccentColor(for role: AccentRole, to palette: AccentPalette) {
        var next = accentColors
        switch role {
        case .monthlyChart:
            next.monthlyChart = palette
        case .dailyChart:
            next.dailyChart = palette
        case .billingChart:
            next.billingChart = palette
        case .widgetRingNormal:
            next.widgetRingNormal = palette
        case .widgetRingWarning50:
            next.widgetRingWarning50 = palette
        case .widgetRingWarning20:
            next.widgetRingWarning20 = palette
        case .usageAlertWarning:
            next.usageAlertWarning = palette
        }

        guard accentColors != next else { return }
        accentColorStore.save(next)
        accentColors = next
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
    }

    func updateDefaultUsageChart(_ newValue: UsageChartDefault) {
        guard displayPreferences.defaultUsageChart != newValue else { return }
        displayPreferences.defaultUsageChart = newValue
        displayPreferenceStore.save(displayPreferences)
    }

    func updateShowsLowSpeedUsage(_ newValue: Bool) {
        guard displayPreferences.showsLowSpeedUsage != newValue else { return }
        displayPreferences.showsLowSpeedUsage = newValue
        displayPreferenceStore.save(displayPreferences)
    }

    func updateShowsBillingChart(_ newValue: Bool) {
        guard displayPreferences.showsBillingChart != newValue else { return }
        displayPreferences.showsBillingChart = newValue
        displayPreferenceStore.save(displayPreferences)
    }

    func updateCalculateTodayFromRemaining(_ newValue: Bool) {
        guard displayPreferences.calculateTodayFromRemaining != newValue else { return }
        displayPreferences.calculateTodayFromRemaining = newValue
        displayPreferenceStore.save(displayPreferences)
    }

    func updateHidePhoneOnScreenshot(_ newValue: Bool) {
        guard displayPreferences.hidePhoneOnScreenshot != newValue else { return }
        displayPreferences.hidePhoneOnScreenshot = newValue
        displayPreferenceStore.save(displayPreferences)
    }

    func updateUsageAlertSettings(_ newValue: UsageAlertSettings) {
        guard usageAlertSettings != newValue else { return }

        usageAlertSettings = newValue
        usageAlertStore.save(usageAlertSettings)
    }

    func updateCommunicationMethod(_ newValue: CommunicationMethod) {
        guard communicationMethod != newValue else { return }
        communicationMethodStore.save(newValue)
        communicationMethod = newValue
        lastLoginSource = nil
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
    }

    var canSubmit: Bool {
        credentialFieldsHidden || currentManualCredentials() != nil
    }

    var loginStatusText: String? {
        guard let source = lastLoginSource else { return nil }
        switch source {
        case .gapiToken:
            return "MyIIJmioトークンで自動ログインしました"
        case .gapiKeychain:
            return "キーチェーンからMyIIJmioへログインしました"
        case .gapiManual:
            return "入力した資格情報でMyIIJmioへログインしました"
        case .sessionCookie:
            return "セッションCookieで自動ログインしました"
        case .keychain:
            return "キーチェーンの資格情報でログインしました"
        case .manual:
            return "入力した資格情報でログインしました"
        case .mock:
            return "モックデータでプレビュー中です"
        }
    }

    func triggerAutomaticRefreshIfNeeded(throttle seconds: TimeInterval = 10 * 60) async {
        let now = Date()
        if let last = lastAutomaticRefresh, now.timeIntervalSince(last) < seconds {
            return
        }
        lastAutomaticRefresh = now
        _ = await refresh(trigger: .automatic)
    }

    func refreshManually() {
        Task { _ = await refresh(trigger: .manual) }
    }

    func fetchBillDetail(for entry: BillSummaryResponse.BillEntry) async throws -> BillDetailResponse {
        return try await widgetRefreshService.fetchBillDetail(
            entry: entry,
            manualCredentials: credentialFieldsHidden ? nil : currentManualCredentials(),
            communicationMethod: communicationMethod
        )
    }

    func revealCredentialFields() {
        credentialFieldsHidden = false
    }

    func logout() throws {
        try credentialStore.delete()
        mioId = ""
        password = ""
        credentialFieldsHidden = false
        lastLoginSource = nil
        hasStoredCredentials = false
        state = .idle
        widgetRefreshService.clearSessionArtifacts()
    }

    /// 更新の入口。既に実行中なら二重に走らせず、その完了を待って同じ結果を返す。
    /// 実際の通信は `inFlightRefresh` の中 (非構造化 Task) で行うので、
    /// 呼び出し元 (引っ張って更新) がキャンセルされても取得処理は最後まで走り切る。
    @discardableResult
    func refresh(trigger: RefreshTrigger) async -> Result<Void, Error> {
        if let inFlight = inFlightRefresh {
            let result = await inFlight.task.value
            // 自動更新に相乗りしただけでは ForceUpdate ヘッダが付かず、
            // 引っ張って更新なのにサーバのキャッシュが返りうる。
            // 手動更新は自動更新の完了を待ってから改めて自前で走らせる。
            guard trigger == .manual, inFlight.trigger == .automatic else { return result }
            guard inFlightRefresh == nil else { return result }
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return Result<Void, Error>.failure(CancellationError()) }
            defer { self.inFlightRefresh = nil }
            return await self.performRefresh(trigger: trigger)
        }
        inFlightRefresh = (trigger, task)
        return await task.value
    }

    private func performRefresh(trigger: RefreshTrigger) async -> Result<Void, Error> {
        let previousPayload = currentPayload()
        state = .loading(previous: previousPayload)

        let manualCredentials = currentManualCredentials()
        let forceManualLogin = manualCredentials != nil && !credentialFieldsHidden

        do {
            let outcome = try await widgetRefreshService.refresh(
                manualCredentials: manualCredentials,
                persistManualCredentials: true,
                allowSessionReuse: !forceManualLogin,
                allowKeychainFallback: !forceManualLogin,
                calculateTodayFromRemaining: displayPreferences.calculateTodayFromRemaining,
                dailyFetchMode: displayPreferences.calculateTodayFromRemaining ? .tableOnly : .mergedPreviewAndTable,
                forceGAPIUpdate: trigger == .manual,
                communicationMethod: communicationMethod
            )
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
            state = .loaded(outcome.payload)
            lastLoginSource = outcome.loginSource
            handleCredentialVisibility(after: outcome.loginSource)
            refreshLogStore.append(
                trigger: trigger.logTrigger,
                result: .success
            )
            return .success(())
        } catch {
            // キャンセルはユーザーに見せるべき失敗ではないので、
            // バナーもログも出さずに直前の状態へ戻す。
            if TaskCancellation.isCancellation(error) {
                state = previousPayload.map { LoadState.loaded($0) } ?? .idle
                return .failure(error)
            }
            state = .failed(error.localizedDescription, lastPayload: previousPayload)
            refreshLogStore.append(
                trigger: trigger.logTrigger,
                result: .failure,
                errorDescription: error.localizedDescription
            )
            return .failure(error)
        }
    }

    private func currentManualCredentials() -> Credentials? {
        let trimmedId = mioId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !password.isEmpty else { return nil }
        return Credentials(mioId: trimmedId, password: password)
    }

    private func currentPayload() -> AggregatePayload? {
        switch state {
        case .loaded(let payload):
            return payload
        case .loading(let previous):
            return previous
        case .failed(_, let last):
            return last
        case .idle:
            return nil
        }
    }

    private func handleCredentialVisibility(after source: WidgetRefreshService.LoginSource) {
        switch source {
        case .gapiToken:
            credentialFieldsHidden = true
        case .gapiKeychain:
            credentialFieldsHidden = true
            if let stored = try? credentialStore.load() {
                mioId = stored.mioId
                password = stored.password
            }
        case .gapiManual:
            credentialFieldsHidden = false
        case .sessionCookie:
            credentialFieldsHidden = true
        case .keychain:
            credentialFieldsHidden = true
            if let stored = try? credentialStore.load() {
                mioId = stored.mioId
                password = stored.password
            }
        case .manual:
            credentialFieldsHidden = false
        case .mock:
            credentialFieldsHidden = true
            if let stored = try? credentialStore.load() {
                mioId = stored.mioId
                password = stored.password
            }
        }
        hasStoredCredentials = (try? credentialStore.load()) != nil
    }

}

private extension AppViewModel.RefreshTrigger {
    var logTrigger: RefreshLogEntry.Trigger {
        switch self {
        case .automatic:
            return .appAutomatic
        case .manual:
            return .appManual
        }
    }
}
