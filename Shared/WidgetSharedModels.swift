import Foundation
import SwiftUI
import UIKit

enum AccentPalette: String, CaseIterable, Identifiable, Codable {
    case ocean          // 旧 IIJブルー
    case mint
    case grape
    case sunset
    case graphite
    case forest
    case sakura
    case citrus
    case midnight
    case sand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ocean:
            return "オーシャン"
        case .mint:
            return "ミント"
        case .grape:
            return "グレープ"
        case .sunset:
            return "サンセット"
        case .graphite:
            return "グラファイト"
        case .forest:
            return "フォレスト"
        case .sakura:
            return "サクラ"
        case .citrus:
            return "シトラス"
        case .midnight:
            return "ミッドナイト"
        case .sand:
            return "サンド"
        }
    }

    var chartGradient: [Color] {
        switch self {
        case .ocean:
            return [
                Color(red: 0.00, green: 0.50, blue: 0.96),
                Color(red: 0.17, green: 0.79, blue: 0.87)
            ]
        case .mint:
            return [
                Color(red: 0.09, green: 0.66, blue: 0.64),
                Color(red: 0.50, green: 0.90, blue: 0.83)
            ]
        case .grape:
            return [
                Color(red: 0.56, green: 0.33, blue: 0.82),
                Color(red: 0.94, green: 0.45, blue: 0.77)
            ]
        case .sunset:
            return [
                Color(red: 0.99, green: 0.61, blue: 0.30),
                Color(red: 0.90, green: 0.21, blue: 0.28)
            ]
        case .graphite:
            return [
                Color(dynamicGraphiteLight: UIColor(red: 0.42, green: 0.45, blue: 0.50, alpha: 1),
                      dark: UIColor(white: 0.90, alpha: 1)),
                Color(dynamicGraphiteLight: UIColor(red: 0.23, green: 0.26, blue: 0.30, alpha: 1),
                      dark: UIColor(white: 0.78, alpha: 1))
            ]
        case .forest:
            return [
                Color(red: 0.16, green: 0.56, blue: 0.35),
                Color(red: 0.39, green: 0.77, blue: 0.48)
            ]
        case .sakura:
            return [
                Color(red: 0.97, green: 0.72, blue: 0.83),
                Color(red: 0.83, green: 0.54, blue: 0.91)
            ]
        case .citrus:
            return [
                Color(red: 0.98, green: 0.82, blue: 0.31),
                Color(red: 0.99, green: 0.55, blue: 0.21)
            ]
        case .midnight:
            return [
                Color(red: 0.13, green: 0.22, blue: 0.44),
                Color(red: 0.32, green: 0.46, blue: 0.78)
            ]
        case .sand:
            return [
                Color(red: 0.94, green: 0.86, blue: 0.70),
                Color(red: 0.92, green: 0.74, blue: 0.48)
            ]
        }
    }

    var widgetRingGradient: [Color] {
        chartGradient.map { $0.opacity(0.98) }
    }

    var secondaryChartGradient: [Color] {
        chartGradient.reversed().map { $0.opacity(0.94) }
    }

    var previewSymbolColor: Color {
        chartGradient.last ?? .accentColor
    }
}

enum AccentRole: CaseIterable {
    case monthlyChart
    case dailyChart
    case billingChart
    case widgetRingNormal
    case widgetRingWarning50
    case widgetRingWarning20
    case usageAlertWarning
}

enum UsageChartDefault: String, Codable {
    case monthly
    case daily
}

struct AccentColorSettings: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case monthlyChart
        case dailyChart
        case billingChart
        case widgetRingNormal
        case widgetRingWarning50
        case widgetRingWarning20
        case usageAlertWarning
    }

    var monthlyChart: AccentPalette
    var dailyChart: AccentPalette
    var billingChart: AccentPalette
    var widgetRingNormal: AccentPalette
    var widgetRingWarning50: AccentPalette
    var widgetRingWarning20: AccentPalette
    var usageAlertWarning: AccentPalette

    static let `default` = AccentColorSettings(
        monthlyChart: .ocean,
        dailyChart: .sakura,
        billingChart: .ocean,
        widgetRingNormal: .forest,
        widgetRingWarning50: .citrus,
        widgetRingWarning20: .sunset,
        usageAlertWarning: .sunset
    )

    init(
        monthlyChart: AccentPalette,
        dailyChart: AccentPalette,
        billingChart: AccentPalette,
        widgetRingNormal: AccentPalette,
        widgetRingWarning50: AccentPalette,
        widgetRingWarning20: AccentPalette,
        usageAlertWarning: AccentPalette
    ) {
        self.monthlyChart = monthlyChart
        self.dailyChart = dailyChart
        self.billingChart = billingChart
        self.widgetRingNormal = widgetRingNormal
        self.widgetRingWarning50 = widgetRingWarning50
        self.widgetRingWarning20 = widgetRingWarning20
        self.usageAlertWarning = usageAlertWarning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthlyChart = try container.decode(AccentPalette.self, forKey: .monthlyChart)
        dailyChart = try container.decode(AccentPalette.self, forKey: .dailyChart)
        billingChart = try container.decodeIfPresent(AccentPalette.self, forKey: .billingChart) ?? .ocean
        widgetRingNormal = try container.decode(AccentPalette.self, forKey: .widgetRingNormal)
        widgetRingWarning50 = try container.decode(AccentPalette.self, forKey: .widgetRingWarning50)
        widgetRingWarning20 = try container.decode(AccentPalette.self, forKey: .widgetRingWarning20)
        usageAlertWarning = try container.decodeIfPresent(AccentPalette.self, forKey: .usageAlertWarning) ?? .sunset
    }

    init(fill palette: AccentPalette) {
        self.init(
            monthlyChart: palette,
            dailyChart: palette,
            billingChart: palette,
            widgetRingNormal: palette,
            widgetRingWarning50: palette,
            widgetRingWarning20: palette,
            usageAlertWarning: palette
        )
    }

    func palette(for role: AccentRole) -> AccentPalette {
        switch role {
        case .monthlyChart:
            return monthlyChart
        case .dailyChart:
            return dailyChart
        case .billingChart:
            return billingChart
        case .widgetRingNormal:
            return widgetRingNormal
        case .widgetRingWarning50:
            return widgetRingWarning50
        case .widgetRingWarning20:
            return widgetRingWarning20
        case .usageAlertWarning:
            return usageAlertWarning
        }
    }

    func widgetRingColors(for ratio: Double) -> [Color] {
        if ratio <= 0.20 {
            return widgetRingWarning20.widgetRingGradient
        } else if ratio <= 0.50 {
            return widgetRingWarning50.widgetRingGradient
        }
        return widgetRingNormal.widgetRingGradient
    }
}

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

private extension Color {
    init(dynamicGraphiteLight light: UIColor, dark: UIColor) {
        self = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }
}

struct DisplayPreferences: Codable, Equatable {
    var defaultUsageChart: UsageChartDefault
    var showsLowSpeedUsage: Bool
    var calculateTodayFromRemaining: Bool

    static let `default` = DisplayPreferences()

    init(
        defaultUsageChart: UsageChartDefault = .monthly,
        showsLowSpeedUsage: Bool = false,
        calculateTodayFromRemaining: Bool = true
    ) {
        self.defaultUsageChart = defaultUsageChart
        self.showsLowSpeedUsage = showsLowSpeedUsage
        self.calculateTodayFromRemaining = calculateTodayFromRemaining
    }

    private enum CodingKeys: String, CodingKey {
        case defaultUsageChart
        case showsLowSpeedUsage
        case calculateTodayFromRemaining
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultUsageChart = try container.decodeIfPresent(UsageChartDefault.self, forKey: .defaultUsageChart) ?? .monthly
        showsLowSpeedUsage = try container.decodeIfPresent(Bool.self, forKey: .showsLowSpeedUsage) ?? false
        calculateTodayFromRemaining = try container.decodeIfPresent(Bool.self, forKey: .calculateTodayFromRemaining) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultUsageChart, forKey: .defaultUsageChart)
        try container.encode(showsLowSpeedUsage, forKey: .showsLowSpeedUsage)
        try container.encode(calculateTodayFromRemaining, forKey: .calculateTodayFromRemaining)
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

    func updatingSuccessUntil(_ date: Date?) -> WidgetSnapshot {
        WidgetSnapshot(
            fetchedAt: fetchedAt,
            primaryService: primaryService,
            isRefreshing: isRefreshing,
            successUntil: date
        )
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
            snapshot = snapshot.updatingRefreshingState(isRefreshing)
            save(snapshot: snapshot)
        } else {
            let placeholder = WidgetSnapshot(fetchedAt: Date(), primaryService: nil, isRefreshing: isRefreshing)
            save(snapshot: placeholder)
        }
        return true
    }

    func setSuccessUntil(_ date: Date?) {
        if var snapshot = loadSnapshot() {
            snapshot = snapshot.updatingSuccessUntil(date)
            save(snapshot: snapshot)
        } else {
            let placeholder = WidgetSnapshot(fetchedAt: Date(), primaryService: nil, isRefreshing: false, successUntil: date)
            save(snapshot: placeholder)
        }
    }

    func clear() {
        AppGroup.userDefaults?.removeObject(forKey: key)
    }
}

struct UsageAlertSettings: Codable, Equatable {
    var isEnabled: Bool
    var monthlyThresholdMB: Int?
    var dailyThresholdMB: Int?

    static let `default` = UsageAlertSettings(
        isEnabled: false,
        monthlyThresholdMB: nil,
        dailyThresholdMB: nil
    )

    func updating(
        isEnabled: Bool? = nil,
        monthlyThresholdMB: Int?? = nil,
        dailyThresholdMB: Int?? = nil
    ) -> UsageAlertSettings {
        var copy = self
        if let isEnabled { copy.isEnabled = isEnabled }
        if let monthlyThresholdMB { copy.monthlyThresholdMB = monthlyThresholdMB }
        if let dailyThresholdMB { copy.dailyThresholdMB = dailyThresholdMB }
        return copy
    }
}

struct UsageAlertStore {
    private let key = "usageAlert.settings.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() -> UsageAlertSettings {
        let defaults = AppGroup.userDefaults ?? UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let decoded = try? decoder.decode(UsageAlertSettings.self, from: data) {
            return decoded
        }
        return .default
    }

    func save(_ settings: UsageAlertSettings) {
        let defaults = AppGroup.userDefaults ?? UserDefaults.standard

        if let data = try? encoder.encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
