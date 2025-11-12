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
    let isRefreshing: Bool

    init(fetchedAt: Date, primaryService: WidgetServiceSnapshot?, isRefreshing: Bool = false) {
        self.fetchedAt = fetchedAt
        self.primaryService = primaryService
        self.isRefreshing = isRefreshing
    }

    static let placeholder = WidgetSnapshot(
        fetchedAt: Date(),
        primaryService: WidgetServiceSnapshot(
            serviceName: "ギガプラン",
            phoneNumber: "070-0000-0000",
            totalCapacityGB: 20,
            remainingGB: 12.4
        ),
        isRefreshing: false
    )

    private enum CodingKeys: String, CodingKey {
        case fetchedAt
        case primaryService
        case isRefreshing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        primaryService = try container.decodeIfPresent(WidgetServiceSnapshot.self, forKey: .primaryService)
        isRefreshing = try container.decodeIfPresent(Bool.self, forKey: .isRefreshing) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encodeIfPresent(primaryService, forKey: .primaryService)
        try container.encode(isRefreshing, forKey: .isRefreshing)
    }

    func updatingRefreshingState(_ isRefreshing: Bool) -> WidgetSnapshot {
        WidgetSnapshot(fetchedAt: fetchedAt, primaryService: primaryService, isRefreshing: isRefreshing)
    }
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

    @discardableResult
    func setRefreshingState(_ isRefreshing: Bool) -> Bool {
        if var snapshot = loadSnapshot() {
            guard snapshot.isRefreshing != isRefreshing else { return false }
            snapshot = snapshot.updatingRefreshingState(isRefreshing)
            save(snapshot: snapshot)
            return true
        } else {
            let placeholder = WidgetSnapshot(fetchedAt: Date(), primaryService: nil, isRefreshing: isRefreshing)
            save(snapshot: placeholder)
            return true
        }
    }
}
