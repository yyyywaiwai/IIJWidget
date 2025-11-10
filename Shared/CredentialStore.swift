import Foundation
import Security

struct CredentialStore {
    private let service = "com.yyyywaiwai.IIJWidget"
    private let account = "IIJCredentials"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let accessGroup = AppGroup.keychainAccessGroup

    func save(_ credentials: Credentials) throws {
        let data = try encoder.encode(credentials)
        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        deleteLegacyCredentialsIfNeeded()
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let query = baseQuery()
            let updateAttributes = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError(status: status)
            }
        default:
            throw KeychainError(status: addStatus)
        }
    }

    func load() throws -> Credentials? {
        if let stored = try loadItem(includeAccessGroup: true) {
            return stored
        }

        if accessGroup != nil, let legacy = try loadItem(includeAccessGroup: false) {
            // migrate legacy entry into shared access group for future widget refreshes
            try? save(legacy)
            return legacy
        }

        return nil
    }

    func delete() throws {
        let primaryStatus = SecItemDelete(baseQuery() as CFDictionary)
        if primaryStatus != errSecSuccess && primaryStatus != errSecItemNotFound {
            throw KeychainError(status: primaryStatus)
        }

        if accessGroup != nil {
            let legacyStatus = SecItemDelete(baseQuery(includeAccessGroup: false) as CFDictionary)
            if legacyStatus != errSecSuccess && legacyStatus != errSecItemNotFound {
                throw KeychainError(status: legacyStatus)
            }
        }
    }

    private func baseQuery(includeAccessGroup: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if includeAccessGroup, let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func loadItem(includeAccessGroup: Bool) throws -> Credentials? {
        var query = baseQuery(includeAccessGroup: includeAccessGroup)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError(status: errSecInternalComponent)
            }
            return try decoder.decode(Credentials.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    private func deleteLegacyCredentialsIfNeeded() {
        guard accessGroup != nil else { return }
        SecItemDelete(baseQuery(includeAccessGroup: false) as CFDictionary)
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}
