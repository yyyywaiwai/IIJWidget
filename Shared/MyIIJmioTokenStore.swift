import Foundation
import Security

struct MyIIJmioSession: Codable, Equatable {
    let token: String
    let mioId: String
    let contractorName: String?
    let appVersion: String
    let createdAt: Date
}

struct MyIIJmioTokenStore {
    private let service = "com.yyyywaiwai.IIJWidget"
    private let account = "MyIIJmioBearerToken.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let accessGroup = AppGroup.keychainAccessGroup

    func save(_ session: MyIIJmioSession) throws {
        let data = try encoder.encode(session)
        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let status = SecItemUpdate(
                baseQuery() as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard status == errSecSuccess else {
                throw KeychainError(status: status)
            }
        default:
            throw KeychainError(status: addStatus)
        }
    }

    func load() throws -> MyIIJmioSession? {
        if let stored = try loadItem(includeAccessGroup: true) {
            return stored
        }

        if accessGroup != nil, let legacy = try loadItem(includeAccessGroup: false) {
            try? save(legacy)
            try? deleteItem(includeAccessGroup: false)
            return legacy
        }

        return nil
    }

    func delete() throws {
        try deleteItem(includeAccessGroup: true)
        if accessGroup != nil {
            try deleteItem(includeAccessGroup: false)
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

    private func loadItem(includeAccessGroup: Bool) throws -> MyIIJmioSession? {
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
            return try decoder.decode(MyIIJmioSession.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    private func deleteItem(includeAccessGroup: Bool) throws {
        let status = SecItemDelete(baseQuery(includeAccessGroup: includeAccessGroup) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
