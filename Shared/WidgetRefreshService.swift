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

    enum FetchScope {
        case full
        case topOnly
    }

    struct RefreshOutcome {
        let payload: AggregatePayload
        let loginSource: LoginSource
    }

    private let credentialStore = CredentialStore()
    private let apiClient = IIJAPIClient()
    private let widgetDataStore = WidgetDataStore()
    private let payloadStore = AggregatePayloadStore()
    private let debugStore = DebugResponseStore.shared

    func refresh(
        manualCredentials: Credentials? = nil,
        persistManualCredentials: Bool = true,
        allowSessionReuse: Bool = true,
        allowKeychainFallback: Bool = true,
        fetchScope: FetchScope = .full
    ) async throws -> RefreshOutcome {
        debugStore.beginCaptureSession()
        defer { debugStore.finalizeCaptureSession() }

        let fallbackPayload = payloadStore.load()

        if allowSessionReuse {
            do {
                return finalize(
                    payload: try await fetchUsingExistingSession(scope: fetchScope, fallback: fallbackPayload),
                    source: .sessionCookie
                )
            } catch IIJAPIClientError.invalidSession {
                // セッションが切れているので次の段階へフォールバック
            }
        }

        if allowKeychainFallback, let stored = try credentialStore.load() {
            do {
                return finalize(
                    payload: try await fetchWithCredentials(stored, scope: fetchScope, fallback: fallbackPayload),
                    source: .keychain
                )
            } catch {
                if apiClient.isAuthenticationError(error) {
                    try? credentialStore.delete()
                } else {
                    throw error
                }
            }
        }

        if let manual = manualCredentials, !manual.mioId.isEmpty, !manual.password.isEmpty {
            let payload = try await fetchWithCredentials(manual, scope: fetchScope, fallback: fallbackPayload)
            if persistManualCredentials {
                try? credentialStore.save(manual)
            }
            return finalize(payload: payload, source: .manual)
        }

        throw WidgetRefreshError.missingCredentials
    }

    private func finalize(payload: AggregatePayload, source: LoginSource) -> RefreshOutcome {
        payloadStore.save(payload: payload)
        let previousSnapshot = widgetDataStore.loadSnapshot()
        if var snapshot = WidgetSnapshot(payload: payload, fallback: previousSnapshot) {
            if previousSnapshot?.isRefreshing == true {
                snapshot = snapshot.updatingRefreshingState(true)
            }
            snapshot = snapshot.updatingSuccessUntil(Date().addingTimeInterval(3))
            widgetDataStore.save(snapshot: snapshot)
        }
        if let formattedPayload = DebugPrettyFormatter.prettyJSONString(payload) {
            debugStore.appendResponse(
                title: "AggregatePayload",
                path: "payload",
                category: .api,
                rawText: formattedPayload,
                formattedText: formattedPayload
            )
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
        widgetDataStore.clear()
    }

    private func fetchUsingExistingSession(scope: FetchScope, fallback: AggregatePayload?) async throws -> AggregatePayload {
        switch scope {
        case .full:
            return try await apiClient.fetchUsingExistingSession()
        case .topOnly:
            let top = try await apiClient.fetchTopUsingExistingSession()
            return buildTopOnlyPayload(top: top, fallback: fallback)
        }
    }

    private func fetchWithCredentials(_ credentials: Credentials, scope: FetchScope, fallback: AggregatePayload?) async throws -> AggregatePayload {
        switch scope {
        case .full:
            return try await apiClient.fetchAll(credentials: credentials)
        case .topOnly:
            let top = try await apiClient.fetchTopOnly(credentials: credentials)
            return buildTopOnlyPayload(top: top, fallback: fallback)
        }
    }

    private func buildTopOnlyPayload(top: MemberTopResponse, fallback: AggregatePayload?) -> AggregatePayload {
        AggregatePayload(
            fetchedAt: Date(),
            top: top,
            bill: fallback?.bill ?? BillSummaryResponse(billList: [], isVoiceSim: nil, isImt: nil),
            serviceStatus: fallback?.serviceStatus ?? ServiceStatusResponse(serviceInfoList: [], jmbNumberChangePossible: nil),
            monthlyUsage: fallback?.monthlyUsage ?? [],
            dailyUsage: fallback?.dailyUsage ?? []
        )
    }
}
