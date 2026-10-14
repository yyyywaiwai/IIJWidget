import Charts
import Foundation
import SwiftUI

struct MonthlyUsageChartCard: View {
    let services: [MonthlyUsageService]
    let accentColor: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    var animationTrigger: AnyHashable? = nil
    @State private var cardWidth: CGFloat = 0
    @State private var chartState = UsageChartState()
    @State private var animateBars = false

    var body: some View {
        UsageChartCardContent(
            kind: .monthly,
            state: $chartState,
            accentColor: accentColor,
            usageAlertSettings: usageAlertSettings,
            animateBars: animateBars,
            animationTrigger: animationTrigger,
            widthChanged: updateCardWidth
        )
        .onAppear {
            rebuildPoints()
            triggerBarAnimation()
        }
        .onChange(of: services) { rebuildPoints() }
        .onChange(of: animationTrigger) { triggerBarAnimation() }
        .onChange(of: chartState.animationToken) { triggerBarAnimation() }
        .onDisappear { animateBars = false }
    }

    private func rebuildPoints() {
        chartState.rebuild(
            points: monthlyChartPoints(from: services),
            displayCount: UsageChartKind.monthly.displayCount(for: cardWidth)
        )
    }

    private func updateCardWidth(_ width: CGFloat) {
        cardWidth = width
        if UsageChartKind.monthly.displayCount(for: width) != chartState.displayCount {
            rebuildPoints()
        }
    }

    private func triggerBarAnimation() {
        animateBars = false
        Task { @MainActor in
            await Task.yield()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.15)) {
                animateBars = true
            }
        }
    }
}

struct DailyUsageChartCard: View {
    let services: [DailyUsageService]
    let accentColor: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    var animationTrigger: AnyHashable? = nil
    @State private var cardWidth: CGFloat = 0
    @State private var chartState = UsageChartState()
    @State private var animateBars = false

    var body: some View {
        UsageChartCardContent(
            kind: .daily,
            state: $chartState,
            accentColor: accentColor,
            usageAlertSettings: usageAlertSettings,
            animateBars: animateBars,
            animationTrigger: animationTrigger,
            widthChanged: updateCardWidth
        )
        .onAppear {
            rebuildPoints()
            triggerBarAnimation()
        }
        .onChange(of: services) { rebuildPoints() }
        .onChange(of: animationTrigger) { triggerBarAnimation() }
        .onChange(of: chartState.animationToken) { triggerBarAnimation() }
        .onDisappear { animateBars = false }
    }

    private func rebuildPoints() {
        chartState.rebuild(
            points: dailyChartPoints(from: services),
            displayCount: UsageChartKind.daily.displayCount(for: cardWidth)
        )
    }

    private func updateCardWidth(_ width: CGFloat) {
        cardWidth = width
        if UsageChartKind.daily.displayCount(for: width) != chartState.displayCount {
            rebuildPoints()
        }
    }

    private func triggerBarAnimation() {
        animateBars = false
        Task { @MainActor in
            await Task.yield()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.15)) {
                animateBars = true
            }
        }
    }
}

/// 月別・日別の違いは表示設定に集約し、描画と選択の実装は共通化する。
private enum UsageChartKind: String {
    case monthly
    case daily

    var title: String { self == .monthly ? "月別データ利用量" : "日別データ利用量" }
    var xAxisTitle: String { self == .monthly ? "月インデックス" : "日インデックス" }
    var unit: String { self == .monthly ? "GB" : "MB" }
    var accentRole: AccentRole { self == .monthly ? .monthlyChart : .dailyChart }
    var cornerRadius: CGFloat { self == .monthly ? 6 : 5 }

    func displayCount(for width: CGFloat) -> Int {
        width > 450 ? (self == .monthly ? 12 : 14) : 7
    }

    func subtitle(displayCount: Int) -> String {
        let period = self == .monthly ? "か月" : "日"
        return "直近\(displayCount)\(period) (\(unit))"
    }

    func valueText(_ value: Double) -> String {
        String(format: self == .monthly ? "%.1fGB" : "%.0fMB", value)
    }

    func exceedsThreshold(_ value: Double, settings: UsageAlertSettings) -> Bool {
        guard settings.isEnabled else { return false }
        switch self {
        case .monthly:
            guard let threshold = settings.monthlyThresholdMB else { return false }
            return settings.exceedsMonthlyThreshold(totalGB: value, threshold: threshold)
        case .daily:
            guard let threshold = settings.dailyThresholdMB else { return false }
            return value > Double(threshold)
        }
    }
}

private struct UsageChartCardContent: View {
    let kind: UsageChartKind
    @Binding var state: UsageChartState
    let accentColor: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    let animateBars: Bool
    let animationTrigger: AnyHashable?
    let widthChanged: (CGFloat) -> Void

    var body: some View {
        DashboardCard(
            title: kind.title,
            subtitle: kind.subtitle(displayCount: state.displayCount > 0 ? state.displayCount : 7)
        ) {
            if state.points.isEmpty {
                ChartPlaceholder(text: "まだデータがありません")
            } else {
                chartContent
                    .frame(height: 220)
            }
        }
    }

    private var chartContent: some View {
        Chart {
            ForEach(state.indexedPoints) { entry in
                BarMark(
                    x: .value(kind.xAxisTitle, Double(entry.index)),
                    y: .value("合計(\(kind.unit))", animateBars ? entry.point.value : 0),
                    width: .fixed(CGFloat(state.barWidth))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors(for: entry.point.value),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: kind.cornerRadius, style: .continuous))
                .opacity(state.selectedIndex == entry.index ? 1.0 : 0.85)
            }

            if let selectedIndex = state.selectedIndex, let selectedPoint = state.selectedPoint {
                RuleMark(
                    x: .value("選択", Double(selectedIndex)),
                    yStart: .value("最小", 0),
                    yEnd: .value("選択値", selectedPoint.value)
                )
                .lineStyle(.init(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(.secondary.opacity(0.6))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: state.axisPositions) { value in
                if let axisValue = value.as(Double.self), let index = state.index(for: axisValue) {
                    AxisGridLine(centered: true)
                    AxisTick(centered: true)
                    AxisValueLabel {
                        Text(state.points[index].displayLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYScale(domain: 0...state.yMaxValue)
        .chartXScale(domain: discreteDomain(forCount: state.points.count))
        .chartXSelection(value: chartSelectionBinding)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    selectionCalloutLayer(proxy: proxy, geometry: geometry)
                        .allowsHitTesting(false)

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if let index = nearestIndex(
                                        from: value.location,
                                        proxy: proxy,
                                        geometry: geometry
                                    ) {
                                        state.selectedIndex = index
                                    }
                                }
                        )
                }
            }
        }
        .id(animationTrigger ?? AnyHashable("\(kind.rawValue)Chart"))
        .padding(.bottom, 18)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { widthChanged(proxy.size.width) }
                    .onChange(of: proxy.size) { _, size in widthChanged(size.width) }
            }
        }
    }

    private var chartSelectionBinding: Binding<Double?> {
        Binding(
            get: { state.selectedIndex.map(Double.init) },
            set: { value in
                guard let value else {
                    state.selectedIndex = nil
                    return
                }
                if let index = state.index(for: value) {
                    state.selectedIndex = index
                }
            }
        )
    }

    private func gradientColors(for value: Double) -> [Color] {
        let role: AccentRole = kind.exceedsThreshold(value, settings: usageAlertSettings)
            ? .usageAlertWarning : kind.accentRole
        return accentColor.palette(for: role).secondaryChartGradient
    }

    @ViewBuilder
    private func selectionCalloutLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        if let plotFrame = proxy.plotFrame {
            let rect = geometry[plotFrame]
            if let selectedIndex = state.selectedIndex,
                let selectedPoint = state.selectedPoint,
                rect != .null,
                let xPosition = proxy.position(forX: Double(selectedIndex))
            {
                let barTopY = proxy.position(forY: selectedPoint.value) ?? 0
                let calloutHeight: CGFloat = 44
                let gap: CGFloat = 8
                let candidateY = rect.minY + barTopY - (calloutHeight + gap)
                let clampedY = max(rect.minY - 12, candidateY)

                ChartCallout(
                    title: selectedPoint.displayLabel,
                    valueText: kind.valueText(selectedPoint.value)
                )
                .position(x: rect.minX + xPosition, y: clampedY)
            }
        }
    }

    private func nearestIndex(from location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Int? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let rect = geometry[plotFrame]
        guard rect != .null else { return nil }
        let relativeX = location.x - rect.minX
        guard relativeX >= 0, relativeX <= rect.width else { return nil }

        var closest: (index: Int, distance: CGFloat)?
        for entry in state.indexedPoints {
            guard let position = proxy.position(forX: Double(entry.index)) else { continue }
            let distance = abs(position - relativeX)
            if let current = closest {
                if distance < current.distance { closest = (entry.index, distance) }
            } else {
                closest = (entry.index, distance)
            }
        }
        return closest?.index
    }
}
