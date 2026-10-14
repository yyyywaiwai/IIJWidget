import SwiftUI

enum AccentRole: CaseIterable {
    case monthlyChart
    case dailyChart
    case billingChart
    case widgetRingNormal
    case widgetRingWarning50
    case widgetRingWarning20
    case usageAlertWarning
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
