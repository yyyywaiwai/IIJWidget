import Foundation

struct AccentColorStore {
    private let keyV2 = "accentColor.preferences.v2"
    private let legacyKey = "accentColor.preference"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() -> AccentColorSettings {
        let defaults = AppGroup.userDefaults ?? UserDefaults.standard
        if let data = defaults.data(forKey: keyV2),
           let decoded = try? decoder.decode(AccentColorSettings.self, from: data) {
            return decoded
        }

        // migrate legacy single preference if exists
        if let raw = defaults.string(forKey: legacyKey),
           let palette = migrateLegacyPalette(rawValue: raw) {
            let migrated = AccentColorSettings(fill: palette)
            save(migrated)
            return migrated
        }

        return .default
    }

    func save(_ preference: AccentColorSettings) {
        let defaults = AppGroup.userDefaults ?? UserDefaults.standard
        if let data = try? encoder.encode(preference) {
            defaults.set(data, forKey: keyV2)
        }
    }

    private func migrateLegacyPalette(rawValue: String) -> AccentPalette? {
        if let palette = AccentPalette(rawValue: rawValue) {
            return palette
        }
        switch rawValue {
        case "mioBlue":
            return .ocean
        default:
            return nil
        }
    }
}
