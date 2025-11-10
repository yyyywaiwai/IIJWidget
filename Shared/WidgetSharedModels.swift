import Foundation

struct WidgetServiceSnapshot: Codable, Equatable {
    let serviceName: String
    let phoneNumber: String
    let totalCapacityGB: Double
    let remainingGB: Double

    var usedGB: Double { max(totalCapacityGB - remainingGB, 0) }
    var usedRatio: Double {
        guard totalCapacityGB > 0 else { return 0 }
        return min(max(usedGB / totalCapacityGB, 0), 1)
    }
}

enum WidgetKind {
    static let remainingData = "RemainingDataWidget"
}

struct WidgetSnapshot: Codable, Equatable {
    let fetchedAt: Date
    let primaryService: WidgetServiceSnapshot?

    static let placeholder = WidgetSnapshot(
        fetchedAt: Date(),
        primaryService: WidgetServiceSnapshot(
            serviceName: "ギガプラン",
            phoneNumber: "070-0000-0000",
            totalCapacityGB: 20,
            remainingGB: 12.4
        )
    )
}

struct WidgetDataStore {
    private let key = "widget.snapshot"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func save(snapshot: WidgetSnapshot) {
        guard let defaults = AppGroup.userDefaults, let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func loadSnapshot() -> WidgetSnapshot? {
        guard let defaults = AppGroup.userDefaults, let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
