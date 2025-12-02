import Foundation

struct RefreshLogEntry: Codable, Identifiable, Equatable {
    enum Trigger: String, Codable, CaseIterable {
        case widgetAutomatic
        case widgetManual
        case appAutomatic
        case appManual

        var displayName: String {
            switch self {
            case .widgetAutomatic:
                return "ウィジェット自動"
            case .widgetManual:
                return "ウィジェット手動"
            case .appAutomatic:
                return "アプリ自動"
            case .appManual:
                return "アプリ手動"
            }
        }
    }

    enum Result: String, Codable {
        case success
        case failure

        var displayName: String {
            switch self {
            case .success:
                return "成功"
            case .failure:
                return "失敗"
            }
        }
    }

    let id: UUID
    let date: Date
    let trigger: Trigger
    let result: Result
    let message: String?
}

struct RefreshLogStore {
    private let key = "widget.refresh.logs.v1"
    private let limit = 50
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var defaults: UserDefaults {
        AppGroup.userDefaults ?? .standard
    }

    func load() -> [RefreshLogEntry] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? decoder.decode([RefreshLogEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    func append(trigger: RefreshLogEntry.Trigger, result: RefreshLogEntry.Result, errorDescription: String? = nil) {
        let entry = RefreshLogEntry(
            id: UUID(),
            date: Date(),
            trigger: trigger,
            result: result,
            message: sanitized(errorDescription)
        )

        var entries = load()
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        save(entries)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func save(_ entries: [RefreshLogEntry]) {
        if let data = try? encoder.encode(entries) {
            defaults.set(data, forKey: key)
        }
    }

    private func sanitized(_ message: String?) -> String? {
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return nil
        }
        return String(message.prefix(200))
    }
}
