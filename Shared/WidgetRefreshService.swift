import Foundation

enum WidgetRefreshError: LocalizedError {
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "キーチェーンに保存された資格情報が見つかりませんでした"
        }
    }
}

struct WidgetRefreshService {
    private let credentialStore = CredentialStore()
    private let apiClient = IIJAPIClient()
    private let widgetDataStore = WidgetDataStore()

    func refresh(using credentialsOverride: Credentials? = nil) async throws -> AggregatePayload {
        let credentials: Credentials
        if let credentialsOverride {
            credentials = credentialsOverride
        } else if let stored = try credentialStore.load() {
            credentials = stored
        } else {
            throw WidgetRefreshError.missingCredentials
        }

        let payload = try await apiClient.fetchAll(credentials: credentials)
        if let snapshot = WidgetSnapshot(payload: payload) {
            widgetDataStore.save(snapshot: snapshot)
        }
        return payload
    }
}
