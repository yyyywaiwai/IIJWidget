import Combine
import Foundation
import WidgetKit

@MainActor
final class AppViewModel: ObservableObject {
    enum RefreshTrigger {
        case automatic
        case manual
        case usageTab
    }

    @Published var mioId: String = ""
    @Published var password: String = ""
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var credentialFieldsHidden = false
    @Published private(set) var lastLoginSource: WidgetRefreshService.LoginSource?
    @Published private(set) var hasStoredCredentials = false
    @Published private(set) var accentColors: AccentColorSettings = .default
    @Published private(set) var displayPreferences: DisplayPreferences = .default
    @Published private(set) var usageAlertSettings: UsageAlertSettings = .default

    private let credentialStore = CredentialStore()
    private let widgetRefreshService = WidgetRefreshService()
    private let payloadStore = AggregatePayloadStore()
    private let accentColorStore = AccentColorStore()
    private let displayPreferenceStore = DisplayPreferencesStore()
    private let usageAlertStore = UsageAlertStore()
    private let refreshLogStore = RefreshLogStore()

    private let refreshCoordinator = RefreshCoordinator<RefreshTrigger>()
    private var sessionGeneration = UUID()
    private var lastAutomaticRefresh: Date?

    init() {
        accentColors = accentColorStore.load()
        displayPreferences = displayPreferenceStore.load()
        usageAlertSettings = usageAlertStore.load()

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

    func refreshUsageHistory() async {
        if state.payload == nil {
            guard case .success = await refresh(trigger: .automatic) else { return }
        }
        _ = await refresh(trigger: .usageTab)
    }

    func fetchBillDetail(for entry: BillSummaryResponse.BillEntry) async throws -> BillDetailResponse {
        return try await widgetRefreshService.fetchBillDetail(
            entry: entry,
            manualCredentials: credentialFieldsHidden ? nil : currentManualCredentials()
        )
    }

    func revealCredentialFields() {
        credentialFieldsHidden = false
    }

    func logout() throws {
        try credentialStore.delete()
        sessionGeneration = UUID()
        refreshCoordinator.cancel()
        lastAutomaticRefresh = nil
        mioId = ""
        password = ""
        credentialFieldsHidden = false
        lastLoginSource = nil
        hasStoredCredentials = false
        state = .idle
        widgetRefreshService.clearSessionArtifacts()
    }

    /// 更新の入口。既に実行中なら二重に走らせず、その完了を待って同じ結果を返す。
    /// 実際の通信は `RefreshCoordinator` の中 (非構造化 Task) で行うので、
    /// 呼び出し元 (引っ張って更新) がキャンセルされても取得処理は最後まで走り切る。
    @discardableResult
    func refresh(trigger: RefreshTrigger) async -> Result<Void, Error> {
        await refreshCoordinator.run(
            trigger: trigger,
            canJoin: { trigger == .automatic && $0 != .usageTab }
        ) { [weak self] in
            guard let self, trigger != .usageTab || self.state.payload != nil else {
                return .failure(CancellationError())
            }
            return await self.performRefresh(trigger: trigger)
        }
    }

    private func performRefresh(trigger: RefreshTrigger) async -> Result<Void, Error> {
        let generation = sessionGeneration
        let previousPayload = state.payload
        state = .loading(previous: previousPayload)

        do {
            if trigger == .usageTab {
                let payload = try await widgetRefreshService.refreshUsageHistory()
                try validateSession(generation)
                state = .loaded(payload)
            } else {
                let manualCredentials = currentManualCredentials()
                let forceManualLogin = manualCredentials != nil && !credentialFieldsHidden
                    && (try? credentialStore.load()) != manualCredentials
                let outcome = try await widgetRefreshService.refresh(
                    manualCredentials: manualCredentials,
                    persistManualCredentials: true,
                    allowSessionReuse: !forceManualLogin,
                    allowKeychainFallback: !forceManualLogin,
                    forceGAPIUpdate: trigger == .manual
                )
                try validateSession(generation)
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
                state = .loaded(outcome.payload)
                lastLoginSource = outcome.loginSource
                handleCredentialVisibility(after: outcome.loginSource)
            }
            refreshLogStore.append(
                trigger: trigger.logTrigger,
                result: .success
            )
            return .success(())
        } catch {
            // An earlier account's completion must never replace the new session's UI.
            guard generation == sessionGeneration else { return .failure(CancellationError()) }
            // キャンセルはユーザーに見せるべき失敗ではないので、
            // バナーもログも出さずに直前の状態へ戻す。
            if Task.isCancelled || TaskCancellation.isCancellation(error) {
                state = canSubmit ? (previousPayload.map { .loaded($0) } ?? .idle) : .idle
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

    private func validateSession(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard generation == sessionGeneration else { throw CancellationError() }
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
        case .usageTab:
            return .appUsageHistory
        }
    }
}
