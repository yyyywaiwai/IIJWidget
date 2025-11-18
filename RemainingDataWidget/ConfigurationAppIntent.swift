import AppIntents
import WidgetKit

struct RemainingDataConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "IIJmio"
    static var description = IntentDescription("IIJmioのデータ残量を表示します。")

    @Parameter(title: "月別グラフカラー", default: .appSetting)
    var monthlyChartColor: WidgetAccentColor

    @Parameter(title: "日別グラフカラー", default: .appSetting)
    var dailyChartColor: WidgetAccentColor

    @Parameter(title: "請求額グラフカラー", default: .appSetting)
    var billingChartColor: WidgetAccentColor

    @Parameter(title: "ウィジェット円カラー (通常)", default: .appSetting)
    var widgetRingColor: WidgetAccentColor

    @Parameter(title: "ウィジェット円カラー (50%以下警告)", default: .appSetting)
    var widgetWarning50Color: WidgetAccentColor

    @Parameter(title: "ウィジェット円カラー (20%以下警告)", default: .appSetting)
    var widgetWarning20Color: WidgetAccentColor

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$monthlyChartColor
            \.$dailyChartColor
            \.$billingChartColor
            \.$widgetRingColor
            \.$widgetWarning50Color
            \.$widgetWarning20Color
        }
    }
}

enum WidgetAccentColor: String, AppEnum {
    case appSetting
    case ocean
    case mint
    case grape
    case sunset
    case graphite
    case forest
    case sakura
    case citrus
    case midnight
    case sand

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "アクセントカラー")

    static var caseDisplayRepresentations: [WidgetAccentColor: DisplayRepresentation] = [
        .appSetting: DisplayRepresentation(title: "アプリ設定を使用"),
        .ocean: DisplayRepresentation(title: "オーシャン"),
        .mint: DisplayRepresentation(title: "ミント"),
        .grape: DisplayRepresentation(title: "グレープ"),
        .sunset: DisplayRepresentation(title: "サンセット"),
        .graphite: DisplayRepresentation(title: "グラファイト"),
        .forest: DisplayRepresentation(title: "フォレスト"),
        .sakura: DisplayRepresentation(title: "サクラ"),
        .citrus: DisplayRepresentation(title: "シトラス"),
        .midnight: DisplayRepresentation(title: "ミッドナイト"),
        .sand: DisplayRepresentation(title: "サンド")
    ]
}

extension WidgetAccentColor {
    var palette: AccentPalette {
        switch self {
        case .appSetting:
            return .ocean // not used directly
        case .ocean:
            return .ocean
        case .mint:
            return .mint
        case .grape:
            return .grape
        case .sunset:
            return .sunset
        case .graphite:
            return .graphite
        case .forest:
            return .forest
        case .sakura:
            return .sakura
        case .citrus:
            return .citrus
        case .midnight:
            return .midnight
        case .sand:
            return .sand
        }
    }

    func resolve(fallback: AccentPalette) -> AccentPalette {
        switch self {
        case .appSetting:
            return fallback
        default:
            return palette
        }
    }
}

extension RemainingDataConfigurationIntent {
    func resolvedAccentSettings(using store: AccentColorStore) -> AccentColorSettings {
        let saved = store.load()
        return AccentColorSettings(
            monthlyChart: monthlyChartColor.resolve(fallback: saved.monthlyChart),
            dailyChart: dailyChartColor.resolve(fallback: saved.dailyChart),
            billingChart: billingChartColor.resolve(fallback: saved.billingChart),
            widgetRingNormal: widgetRingColor.resolve(fallback: saved.widgetRingNormal),
            widgetRingWarning50: widgetWarning50Color.resolve(fallback: saved.widgetRingWarning50),
            widgetRingWarning20: widgetWarning20Color.resolve(fallback: saved.widgetRingWarning20)
        )
    }
}
