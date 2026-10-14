import Foundation

struct WidgetServiceSnapshot: Codable, Equatable {
    let serviceName: String
    let phoneNumber: String
    let totalCapacityGB: Double
    let remainingGB: Double

    var usedGB: Double { max(totalCapacityGB - remainingGB, 0) }

    var remainingRatio: Double {
        guard totalCapacityGB > 0 else { return 0 }
        return min(max(remainingGB / totalCapacityGB, 0), 1)
    }

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
    let successUntil: Date?

    init(
        fetchedAt: Date,
        primaryService: WidgetServiceSnapshot?,
        isRefreshing: Bool = false,
        successUntil: Date? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.primaryService = primaryService
        self.isRefreshing = isRefreshing
        self.successUntil = successUntil
    }

    static let placeholder = WidgetSnapshot(
        fetchedAt: Date(),
        primaryService: WidgetServiceSnapshot(
            serviceName: "ギガプラン",
            phoneNumber: "070-0000-0000",
            totalCapacityGB: 20,
            remainingGB: 12.4
        ),
        isRefreshing: false,
        successUntil: nil
    )

    private enum CodingKeys: String, CodingKey {
        case fetchedAt
        case primaryService
        case isRefreshing
        case successUntil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        primaryService = try container.decodeIfPresent(WidgetServiceSnapshot.self, forKey: .primaryService)
        isRefreshing = try container.decodeIfPresent(Bool.self, forKey: .isRefreshing) ?? false
        successUntil = try container.decodeIfPresent(Date.self, forKey: .successUntil)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encodeIfPresent(primaryService, forKey: .primaryService)
        try container.encode(isRefreshing, forKey: .isRefreshing)
        try container.encodeIfPresent(successUntil, forKey: .successUntil)
    }

    func updatingRefreshingState(_ isRefreshing: Bool) -> WidgetSnapshot {
        WidgetSnapshot(
            fetchedAt: fetchedAt,
            primaryService: primaryService,
            isRefreshing: isRefreshing,
            successUntil: successUntil
        )
    }

    func showsSuccess(at date: Date) -> Bool {
        successUntil.map { $0 > date } ?? false
    }

    func updatingSuccessUntil(_ date: Date?) -> WidgetSnapshot {
        WidgetSnapshot(
            fetchedAt: fetchedAt,
            primaryService: primaryService,
            isRefreshing: isRefreshing,
            successUntil: date
        )
    }
}
