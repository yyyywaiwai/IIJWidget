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

    private let credentialStore = CredentialStore()
    private let widgetRefreshService = WidgetRefreshService()
    private let payloadStore = AggregatePayloadStore()

    private var refreshTaskInFlight = false
    private var lastAutomaticRefresh: Date?

    init() {
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
}
