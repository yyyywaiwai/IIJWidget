import SwiftUI
import UIKit

enum AccentPalette: String, CaseIterable, Identifiable, Codable {
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
    case coral
    case lavender
    case teal
    case ruby
    case gold
    case emerald
    case indigo
    case peach
    case slate
    case rose
    case aqua
    case crimson
    case lime
    case violet
    case bronze

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
        case .coral:
            return "コーラル"
        case .lavender:
            return "ラベンダー"
        case .teal:
            return "ティール"
        case .ruby:
            return "ルビー"
        case .gold:
            return "ゴールド"
        case .emerald:
            return "エメラルド"
        case .indigo:
            return "インディゴ"
        case .peach:
            return "ピーチ"
        case .slate:
            return "スレート"
        case .rose:
            return "ローズ"
        case .aqua:
            return "アクア"
        case .crimson:
            return "クリムゾン"
        case .lime:
            return "ライム"
        case .violet:
            return "バイオレット"
        case .bronze:
            return "ブロンズ"
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
                Color(red: 0.90, green: 0.21, blue: 0.28),
                Color(red: 0.99, green: 0.61, blue: 0.30)
            ]
        case .graphite:
            return [
                Color(dynamicGraphiteLight: UIColor(red: 0.23, green: 0.26, blue: 0.30, alpha: 1),
                      dark: UIColor(white: 0.78, alpha: 1)),
                Color(dynamicGraphiteLight: UIColor(red: 0.42, green: 0.45, blue: 0.50, alpha: 1),
                      dark: UIColor(white: 0.90, alpha: 1))
            ]
        case .forest:
            return [
                Color(red: 0.16, green: 0.56, blue: 0.35),
                Color(red: 0.39, green: 0.77, blue: 0.48)
            ]
        case .sakura:
            return [
                Color(red: 0.83, green: 0.54, blue: 0.91),
                Color(red: 0.97, green: 0.72, blue: 0.83)
            ]
        case .citrus:
            return [
                Color(red: 0.99, green: 0.55, blue: 0.21),
                Color(red: 0.98, green: 0.82, blue: 0.31)
            ]
        case .midnight:
            return [
                Color(red: 0.13, green: 0.22, blue: 0.44),
                Color(red: 0.32, green: 0.46, blue: 0.78)
            ]
        case .sand:
            return [
                Color(red: 0.92, green: 0.74, blue: 0.48),
                Color(red: 0.94, green: 0.86, blue: 0.70)
            ]
        case .coral:
            return [
                Color(red: 1.00, green: 0.50, blue: 0.45),
                Color(red: 1.00, green: 0.70, blue: 0.60)
            ]
        case .lavender:
            return [
                Color(red: 0.70, green: 0.55, blue: 0.90),
                Color(red: 0.85, green: 0.75, blue: 0.95)
            ]
        case .teal:
            return [
                Color(red: 0.00, green: 0.55, blue: 0.55),
                Color(red: 0.25, green: 0.75, blue: 0.75)
            ]
        case .ruby:
            return [
                Color(red: 0.88, green: 0.07, blue: 0.37),
                Color(red: 0.95, green: 0.35, blue: 0.50)
            ]
        case .gold:
            return [
                Color(red: 1.00, green: 0.68, blue: 0.26),
                Color(red: 1.00, green: 0.84, blue: 0.00)
            ]
        case .emerald:
            return [
                Color(red: 0.00, green: 0.60, blue: 0.40),
                Color(red: 0.20, green: 0.80, blue: 0.55)
            ]
        case .indigo:
            return [
                Color(red: 0.29, green: 0.00, blue: 0.51),
                Color(red: 0.45, green: 0.25, blue: 0.70)
            ]
        case .peach:
            return [
                Color(red: 1.00, green: 0.80, blue: 0.64),
                Color(red: 1.00, green: 0.63, blue: 0.48)
            ]
        case .slate:
            return [
                Color(red: 0.44, green: 0.50, blue: 0.56),
                Color(red: 0.60, green: 0.68, blue: 0.75)
            ]
        case .rose:
            return [
                Color(red: 0.95, green: 0.30, blue: 0.50),
                Color(red: 1.00, green: 0.55, blue: 0.65)
            ]
        case .aqua:
            return [
                Color(red: 0.00, green: 0.80, blue: 0.95),
                Color(red: 0.40, green: 0.90, blue: 1.00)
            ]
        case .crimson:
            return [
                Color(red: 0.70, green: 0.15, blue: 0.25),
                Color(red: 0.86, green: 0.08, blue: 0.24)
            ]
        case .lime:
            return [
                Color(red: 0.50, green: 0.85, blue: 0.20),
                Color(red: 0.70, green: 0.95, blue: 0.40)
            ]
        case .violet:
            return [
                Color(red: 0.55, green: 0.25, blue: 0.70),
                Color(red: 0.75, green: 0.45, blue: 0.85)
            ]
        case .bronze:
            return [
                Color(red: 0.80, green: 0.50, blue: 0.20),
                Color(red: 0.90, green: 0.65, blue: 0.40)
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

private extension Color {
    init(dynamicGraphiteLight light: UIColor, dark: UIColor) {
        self = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }
}
