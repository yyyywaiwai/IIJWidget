import Combine
import Foundation
import SwiftUI
import WidgetKit
import UserNotifications

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

    private let credentialStore = CredentialStore()
    private let widgetRefreshService = WidgetRefreshService()
    private let payloadStore = AggregatePayloadStore()
    private let accentColorStore = AccentColorStore()
    private let displayPreferenceStore = DisplayPreferencesStore()
    private let usageAlertStore = UsageAlertStore()
    private let usageAlertChecker = UsageAlertChecker()

    private var refreshTaskInFlight = false
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

    func updateUsageAlertSettings(_ newValue: UsageAlertSettings) {
        guard usageAlertSettings != newValue else { return }
        
        // Check if thresholds changed
        let monthlyThresholdChanged = usageAlertSettings.monthlyThresholdMB != newValue.monthlyThresholdMB
        let dailyThresholdChanged = usageAlertSettings.dailyThresholdMB != newValue.dailyThresholdMB
        
        usageAlertSettings = newValue
        usageAlertStore.save(usageAlertSettings)
        
        // Reset notification limits if thresholds changed
        if monthlyThresholdChanged || dailyThresholdChanged {
            let defaults = UserDefaults(suiteName: "group.com.yyyywaiwai.IIJWidget") ?? .standard
            if monthlyThresholdChanged {
                defaults.removeObject(forKey: "lastMonthlyAlertDate")
                print("🔄 Monthly threshold changed, reset notification limit")
            }
            if dailyThresholdChanged {
                defaults.removeObject(forKey: "lastDailyAlertDate")
                print("🔄 Daily threshold changed, reset notification limit")
            }
        }
        
        if newValue.isEnabled && newValue.sendNotification {
            Task {
                await requestNotificationPermission()
            }
        }
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    var canSubmit: Bool {
        credentialFieldsHidden || currentManualCredentials() != nil
    }

    var loginStatusText: String? {
        guard let source = lastLoginSource else { return nil }
        switch source {
        case .sessionCookie:
            return "セッションCookieで自動ログインしました"
        case .keychain:
            return "キーチェーンの資格情報でログインしました"
        case .manual:
            return "入力した資格情報でログインしました"
        }
    }

    func triggerAutomaticRefreshIfNeeded(throttle seconds: TimeInterval = 10 * 60) async {
        let now = Date()
        if let last = lastAutomaticRefresh, now.timeIntervalSince(last) < seconds {
            return
        }
        lastAutomaticRefresh = now
        await refresh(trigger: .automatic)
    }

    func refreshManually() {
        Task { await refresh(trigger: .manual) }
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
        mioId = ""
        password = ""
        credentialFieldsHidden = false
        lastLoginSource = nil
        hasStoredCredentials = false
        state = .idle
        widgetRefreshService.clearSessionArtifacts()
    }

    private func refresh(trigger: RefreshTrigger) async {
        guard !refreshTaskInFlight else { return }
        refreshTaskInFlight = true
        let previousPayload = currentPayload()
        state = .loading(previous: previousPayload)
        defer { refreshTaskInFlight = false }

        do {
            let outcome = try await widgetRefreshService.refresh(
                manualCredentials: currentManualCredentials(),
                persistManualCredentials: true,
                allowSessionReuse: true,
                allowKeychainFallback: true
            )
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
            state = .loaded(outcome.payload)
            lastLoginSource = outcome.loginSource
            handleCredentialVisibility(after: outcome.loginSource)
            Task {
                await usageAlertChecker.checkUsageAlerts(payload: outcome.payload)
            }
        } catch {
            state = .failed(error.localizedDescription, lastPayload: previousPayload)
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
        }
        hasStoredCredentials = (try? credentialStore.load()) != nil
    }



    func sendTestNotification() {
        Task {
            await requestNotificationPermission()
            let content = UNMutableNotificationContent()
            content.title = "テスト通知"
            content.body = "これはテスト通知です。通知機能は正常に動作しています。"
            content.sound = .default

            let request = UNNotificationRequest(identifier: "test_notification_\(Date().timeIntervalSince1970)", content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
