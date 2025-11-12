import Combine
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppViewModel: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case loaded(AggregatePayload)
        case failed(String)
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

    private var isRefreshing = false
    private var lastAutomaticRefresh: Date?

    init() {
        if let saved = try? credentialStore.load() {
            mioId = saved.mioId
            password = saved.password
            credentialFieldsHidden = true
            hasStoredCredentials = true
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

    func triggerAutomaticRefreshIfNeeded(throttle seconds: TimeInterval = 60) async {
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
        guard !isRefreshing else { return }
        isRefreshing = true
        state = .loading
        defer { isRefreshing = false }

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
            state = .failed(error.localizedDescription)
        }
    }

    private func currentManualCredentials() -> Credentials? {
        let trimmedId = mioId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !password.isEmpty else { return nil }
        return Credentials(mioId: trimmedId, password: password)
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
