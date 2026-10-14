import Foundation

enum UsageChartDefault: String, Codable {
    case monthly
    case daily
}

struct DisplayPreferences: Codable, Equatable {
    var defaultUsageChart: UsageChartDefault
    var showsLowSpeedUsage: Bool
    var showsBillingChart: Bool
    var hidePhoneOnScreenshot: Bool

    static let `default` = DisplayPreferences()

    init(
        defaultUsageChart: UsageChartDefault = .monthly,
        showsLowSpeedUsage: Bool = false,
        showsBillingChart: Bool = false,
        hidePhoneOnScreenshot: Bool = true
    ) {
        self.defaultUsageChart = defaultUsageChart
        self.showsLowSpeedUsage = showsLowSpeedUsage
        self.showsBillingChart = showsBillingChart
        self.hidePhoneOnScreenshot = hidePhoneOnScreenshot
    }

    private enum CodingKeys: String, CodingKey {
        case defaultUsageChart
        case showsLowSpeedUsage
        case showsBillingChart
        case hidePhoneOnScreenshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultUsageChart = try container.decodeIfPresent(UsageChartDefault.self, forKey: .defaultUsageChart) ?? .monthly
        showsLowSpeedUsage = try container.decodeIfPresent(Bool.self, forKey: .showsLowSpeedUsage) ?? false
        showsBillingChart = try container.decodeIfPresent(Bool.self, forKey: .showsBillingChart) ?? false
        hidePhoneOnScreenshot = try container.decodeIfPresent(Bool.self, forKey: .hidePhoneOnScreenshot) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultUsageChart, forKey: .defaultUsageChart)
        try container.encode(showsLowSpeedUsage, forKey: .showsLowSpeedUsage)
        try container.encode(showsBillingChart, forKey: .showsBillingChart)
        try container.encode(hidePhoneOnScreenshot, forKey: .hidePhoneOnScreenshot)
    }
}

struct DisplayPreferencesStore {
    private let key = "display.preferences.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() -> DisplayPreferences {
        let defaults = AppGroup.userDefaults ?? UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let decoded = try? decoder.decode(DisplayPreferences.self, from: data) {
            return decoded
        }
        return .default
    }

    func save(_ preferences: DisplayPreferences) {
        let defaults = AppGroup.userDefaults ?? UserDefaults.standard
        if let data = try? encoder.encode(preferences) {
            defaults.set(data, forKey: key)
        }
    }
}
