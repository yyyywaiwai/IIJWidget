import Foundation

enum AppGroup {
    static let identifier = "group.jp.yyyywaiwai.miowidgetgroup" // TODO: update to your actual App Group ID

    static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
    
    static var keychainAccessGroup: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String else {
            return nil
        }
        return "\(prefix)jp.yyyywaiwai.MioWidget"
    }
}
