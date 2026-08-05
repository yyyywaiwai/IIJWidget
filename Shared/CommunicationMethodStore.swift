import Foundation

struct CommunicationMethodStore {
    private let key = "communication.method.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.userDefaults ?? .standard) {
        self.defaults = defaults
    }

    func load() -> CommunicationMethod {
        guard let rawValue = defaults.string(forKey: key),
              let method = CommunicationMethod(rawValue: rawValue) else {
            return .myIIJmioGAPI
        }
        return method
    }

    func save(_ method: CommunicationMethod) {
        defaults.set(method.rawValue, forKey: key)
    }
}
