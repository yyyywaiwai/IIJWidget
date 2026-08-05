import Foundation

@main
enum CommunicationMethodValidation {
    static func main() throws {
        let suiteName = "CommunicationMethodValidation.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw ValidationError.failedToCreateDefaults
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CommunicationMethodStore(defaults: defaults)
        try require(store.load() == .myIIJmioGAPI, "既定値が新形式ではありません")

        store.save(.legacyMemberSite)
        try require(store.load() == .legacyMemberSite, "従来方式を保存できません")

        store.save(.myIIJmioGAPI)
        try require(store.load() == .myIIJmioGAPI, "新形式へ戻せません")

        defaults.set("unknown", forKey: "communication.method.v1")
        try require(store.load() == .myIIJmioGAPI, "不明な保存値が安全な既定値へ戻りません")

        print("COMMUNICATION_METHOD_STORE_OK default=gapi switch=legacy restore=gapi")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ValidationError.assertionFailed(message) }
    }
}

private enum ValidationError: LocalizedError {
    case failedToCreateDefaults
    case assertionFailed(String)

    var errorDescription: String? {
        switch self {
        case .failedToCreateDefaults:
            return "検証用UserDefaultsを作成できませんでした"
        case .assertionFailed(let message):
            return message
        }
    }
}
