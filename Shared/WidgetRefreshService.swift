import Foundation

enum WidgetRefreshError: LocalizedError {
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "キーチェーンまたは入力済みの資格情報が見つかりませんでした"
        }
    }
}

struct WidgetRefreshService {
    enum LoginSource {
        case sessionCookie
        case keychain
        case manual
    }

    struct RefreshOutcome {
        let payload: AggregatePayload
        let loginSource: LoginSource
    }

    private let credentialStore = CredentialStore()
    private let apiClient = IIJAPIClient()
    private let widgetDataStore = WidgetDataStore()

    func refresh(
        manualCredentials: Credentials? = nil,
        persistManualCredentials: Bool = true,
        allowSessionReuse: Bool = true,
        allowKeychainFallback: Bool = true
    ) async throws -> RefreshOutcome {
        if allowSessionReuse {
            do {
                return finalize(payload: try await apiClient.fetchUsingExistingSession(), source: .sessionCookie)
            } catch IIJAPIClientError.invalidSession {
                // セッションが切れているので次の段階へフォールバック
            }
        }

        if allowKeychainFallback, let stored = try credentialStore.load() {
            do {
                return finalize(payload: try await apiClient.fetchAll(credentials: stored), source: .keychain)
            } catch {
                if apiClient.isAuthenticationError(error) {
                    try? credentialStore.delete()
                } else {
                    throw error
                }
            }
        }

        if let manual = manualCredentials, !manual.mioId.isEmpty, !manual.password.isEmpty {
            let payload = try await apiClient.fetchAll(credentials: manual)
            if persistManualCredentials {
                try? credentialStore.save(manual)
            }
            return finalize(payload: payload, source: .manual)
        }

        throw WidgetRefreshError.missingCredentials
    }

    private func finalize(payload: AggregatePayload, source: LoginSource) -> RefreshOutcome {
        if let snapshot = WidgetSnapshot(payload: payload) {
            widgetDataStore.save(snapshot: snapshot)
        }
        return RefreshOutcome(payload: payload, loginSource: source)
    }

    func clearSessionArtifacts() {
        apiClient.clearPersistedSession()
    }
}
