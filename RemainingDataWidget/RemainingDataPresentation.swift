import SwiftUI

/// すべての表示サイズで同じ値・更新状態・警告色を使用する。
struct RemainingDataPresentation {
    let entry: RemainingDataEntry
    let showsSuccess: Bool

    init(entry: RemainingDataEntry, now: Date = Date()) {
        self.entry = entry
        showsSuccess = entry.snapshot?.showsSuccess(at: now) == true
    }

    var service: WidgetServiceSnapshot? { entry.snapshot?.primaryService }
    var isRefreshing: Bool { entry.snapshot?.isRefreshing == true }
    var fetchedAt: Date { entry.snapshot?.fetchedAt ?? entry.date }

    var title: String {
        if showsSuccess { return "更新完了" }
        if isRefreshing { return "更新中..." }
        return service?.serviceName ?? "IIJmio"
    }

    func ringColors(for ratio: Double) -> [Color] {
        entry.accentColors.widgetRingColors(for: ratio)
    }
}

enum WidgetDataText {
    static func gigabytes(_ value: Double, size: CGFloat, weight: Font.Weight, compact: Bool = false) -> Text {
        Text(String(format: compact ? "%.1f" : "%.2f", value))
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
    }

    static func gigabytesWithUnit(_ value: Double) -> String {
        String(format: "%.2fGB", value)
    }

    static func inlineRemaining(for service: WidgetServiceSnapshot) -> Text {
        let size: CGFloat = 12
        let unitFont = Font.system(size: size * 0.85, weight: .semibold, design: .rounded)
        return Text("残")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            + gigabytes(service.remainingGB, size: size, weight: .semibold)
            + Text("GB / ").font(unitFont)
            + gigabytes(service.totalCapacityGB, size: size, weight: .semibold)
            + Text("GB").font(unitFont)
    }
}
