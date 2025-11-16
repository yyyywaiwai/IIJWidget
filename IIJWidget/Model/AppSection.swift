import Foundation

enum AppSection: Hashable {
    case home
    case usage
    case billing
    case settings

    var title: String {
        switch self {
        case .home:
            return "ホーム"
        case .usage:
            return "利用量"
        case .billing:
            return "請求"
        case .settings:
            return "設定"
        }
    }

    var iconName: String {
        switch self {
        case .home:
            return "house"
        case .usage:
            return "chart.bar"
        case .billing:
            return "yensign"
        case .settings:
            return "gearshape"
        }
    }
}
