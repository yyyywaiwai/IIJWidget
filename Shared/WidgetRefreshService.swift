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
    private let payloadStore = AggregatePayloadStore()

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
        payloadStore.save(payload: payload)
        if var snapshot = WidgetSnapshot(payload: payload) {
            if widgetDataStore.loadSnapshot()?.isRefreshing == true {
                snapshot = snapshot.updatingRefreshingState(true)
            }
            widgetDataStore.save(snapshot: snapshot)
        }
        return RefreshOutcome(payload: payload, loginSource: source)
    }

    func fetchBillDetail(entry: BillSummaryResponse.BillEntry, manualCredentials: Credentials? = nil) async throws -> BillDetailResponse {
        do {
            return try await apiClient.fetchBillDetail(entry: entry)
        } catch {
            guard apiClient.isAuthenticationError(error) else { throw error }
        }

        if let stored = try? credentialStore.load() {
            do {
                return try await apiClient.fetchBillDetail(entry: entry, credentials: stored)
            } catch {
                if apiClient.isAuthenticationError(error) {
                    try? credentialStore.delete()
                } else {
                    throw error
                }
            }
        }

        if let manual = manualCredentials {
            return try await apiClient.fetchBillDetail(entry: entry, credentials: manual)
        }

        throw WidgetRefreshError.missingCredentials
    }

    func clearSessionArtifacts() {
        apiClient.clearPersistedSession()
        payloadStore.clear()
    }
}
