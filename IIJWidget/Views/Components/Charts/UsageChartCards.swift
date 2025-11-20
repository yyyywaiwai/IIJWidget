import SwiftUI
import Charts

struct MonthlyUsageChartCard: View {
    let services: [MonthlyUsageService]
    let accentColor: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    @State private var selectedIndex: Int?
    private var points: [UsageChartPoint] {
        monthlyChartPoints(from: services)
    }
    private var indexedPoints: [(index: Int, point: UsageChartPoint)] {
        points.enumerated().map { (index: $0.offset, point: $0.element) }
    }
    private var selectedPoint: UsageChartPoint? {
        guard let selectedIndex, indexedPoints.indices.contains(selectedIndex) else { return nil }
        return indexedPoints[selectedIndex].point
    }
    private var defaultSelectionIndex: Int? {
        indexedPoints.last?.index
    }

    var body: some View {
        DashboardCard(title: "月別データ利用量", subtitle: "直近6か月 (GB)") {
            if indexedPoints.isEmpty {
                ChartPlaceholder(text: "まだデータがありません")
            } else {
                chartContent
                    .frame(height: 220)
                    .onAppear { selectedIndex = defaultSelectionIndex }
                    .onChange(of: services) { _ in selectedIndex = defaultSelectionIndex }
            }
        }
    }

    private var chartContent: some View {
        Chart {
            ForEach(indexedPoints, id: \.point.id) { entry in
                BarMark(
                    x: .value("月インデックス", centeredValue(for: entry.index)),
                    y: .value("合計(GB)", entry.point.value),
                    width: .fixed(28)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors(for: entry.point.value),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            }

            if let selectedIndex, let selectedPoint {
                RuleMark(x: .value("選択", centeredValue(for: selectedIndex)))
                    .lineStyle(.init(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .center) {
                        ChartCallout(
                            title: selectedPoint.displayLabel,
                            valueText: String(format: "%.1fGB", selectedPoint.value)
                        )
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: axisPositions) { value in
                if let doubleValue = value.as(Double.self),
                   let index = index(from: doubleValue),
                   indexedPoints.indices.contains(index) {
                    AxisGridLine(centered: true)
                    AxisTick(centered: true)
                }
            }
        }
        .chartXScale(domain: discreteDomain(forCount: indexedPoints.count))
        .chartXSelection(value: chartSelectionBinding)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    axisLabelsLayer(proxy: proxy, geometry: geometry)
                        .allowsHitTesting(false)

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard !indexedPoints.isEmpty else { return }
                                    let plotFrame = proxy.plotAreaFrame
                                    let frameRect = geometry[plotFrame]
                                    let origin = frameRect.origin
                                    let xPosition = value.location.x - origin.x
                                    guard xPosition >= 0, xPosition <= frameRect.width else { return }
                                    if let axisValue: Double = proxy.value(atX: xPosition),
                                       let newIndex = index(from: axisValue) {
                                        selectedIndex = newIndex
                                    }
                                }
                        )
                }
            }
        }
        .padding(.bottom, axisLabelPadding)
    }

    private var axisPositions: [Double] {
        indexedPoints.map { centeredValue(for: $0.index) }
    }

    private var chartSelectionBinding: Binding<Double?> {
        Binding(
            get: {
                guard let selectedIndex else { return nil }
                return centeredValue(for: selectedIndex)
            },
            set: { newValue in
                guard let newValue else {
                    selectedIndex = nil
                    return
                }
                if let nextIndex = index(from: newValue) {
                    selectedIndex = nextIndex
                }
            }
        )
    }

    private func centeredValue(for index: Int) -> Double {
        Double(index)
    }

    private var axisLabelPadding: CGFloat { 18 }

    @ViewBuilder
    private func axisLabelsLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        let plotFrame = proxy.plotAreaFrame
        let rect = geometry[plotFrame]
        ZStack(alignment: .topLeading) {
            ForEach(indexedPoints, id: \.point.id) { entry in
                if let xPosition = proxy.position(forX: centeredValue(for: entry.index)) {
                    Text(entry.point.displayLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(
                            x: rect.minX + xPosition,
                            y: rect.maxY + axisLabelPadding
                        )
                }
            }
        }
    }

    private func index(from value: Double) -> Int? {
        guard !indexedPoints.isEmpty else { return nil }
        let lowerBound = 0.0
        let upperBound = Double(indexedPoints.count - 1)
        let normalized = min(max(value, lowerBound), upperBound)
        let derived = Int(normalized.rounded())
        guard indexedPoints.indices.contains(derived) else { return nil }
        return derived
    }

    private func gradientColors(for valueGB: Double) -> [Color] {
        if usageAlertSettings.isEnabled,
           let thresholdMB = usageAlertSettings.monthlyThresholdMB,
           (valueGB * 1024) > Double(thresholdMB) {
            return accentColor.palette(for: .usageAlertWarning).secondaryChartGradient
        }
        return accentColor.palette(for: .monthlyChart).secondaryChartGradient
    }
}

struct DailyUsageChartCard: View {
    let services: [DailyUsageService]
    let accentColor: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    @State private var selectedIndex: Int?

    private var points: [UsageChartPoint] {
        dailyChartPoints(from: services)
    }

    private var visiblePoints: [UsageChartPoint] {
        Array(points.suffix(7))
    }

    private var indexedPoints: [(index: Int, point: UsageChartPoint)] {
        visiblePoints.enumerated().map { (index: $0.offset, point: $0.element) }
    }

    private var selectedPoint: UsageChartPoint? {
        guard let selectedIndex, visiblePoints.indices.contains(selectedIndex) else {
            return nil
        }
        return visiblePoints[selectedIndex]
    }

    private var defaultSelectionIndex: Int? {
        indexedPoints.last?.index
    }

    var body: some View {
        DashboardCard(title: "日別データ利用量", subtitle: "履歴 (MB)") {
            if indexedPoints.isEmpty {
                ChartPlaceholder(text: "まだデータがありません")
            } else {
                chartContent
                    .frame(height: 220)
                    .onAppear { selectedIndex = defaultSelectionIndex }
                    .onChange(of: services) { _ in selectedIndex = defaultSelectionIndex }
            }
        }
    }

    private var chartContent: some View {
        Chart {
            ForEach(indexedPoints, id: \.point.id) { entry in
                BarMark(
                    x: .value("日インデックス", centeredValue(for: entry.index)),
                    y: .value("合計(MB)", entry.point.value),
                    width: .fixed(barWidth)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors(for: entry.point.value),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            }

            if let selectedIndex, let selectedPoint {
                RuleMark(x: .value("選択", centeredValue(for: selectedIndex)))
                    .lineStyle(.init(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .center) {
                        ChartCallout(title: selectedPoint.displayLabel, valueText: String(format: "%.0fMB", selectedPoint.value))
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: axisPositions) { value in
                if let doubleValue = value.as(Double.self),
                   let index = index(from: doubleValue),
                   indexedPoints.indices.contains(index) {
                    AxisGridLine(centered: true)
                    AxisTick(centered: true)
                }
            }
        }
        .chartXScale(domain: discreteDomain(forCount: indexedPoints.count))
        .chartXSelection(value: chartSelectionBinding)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    axisLabelsLayer(proxy: proxy, geometry: geometry)
                        .allowsHitTesting(false)

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard !indexedPoints.isEmpty else { return }
                                    let plotFrame = proxy.plotAreaFrame
                                    let frameRect = geometry[plotFrame]
                                    let origin = frameRect.origin
                                    let xPosition = value.location.x - origin.x
                                    guard xPosition >= 0, xPosition <= frameRect.width else { return }
                                    if let axisValue: Double = proxy.value(atX: xPosition),
                                       let newIndex = index(from: axisValue) {
                                        selectedIndex = newIndex
                                    }
                                }
                        )
                }
            }
        }
        .padding(.bottom, axisLabelPadding)
    }

    private var axisPositions: [Double] {
        indexedPoints.map { centeredValue(for: $0.index) }
    }

    private var barWidth: CGFloat {
        let totalCount = max(1, indexedPoints.count)
        let availableWidth: CGFloat = 260
        let computed = availableWidth / CGFloat(totalCount)
        return max(4, min(20, computed))
    }

    private var chartSelectionBinding: Binding<Double?> {
        Binding(
            get: {
                guard let selectedIndex else { return nil }
                return centeredValue(for: selectedIndex)
            },
            set: { newValue in
                guard let newValue else {
                    selectedIndex = nil
                    return
                }
                if let nextIndex = index(from: newValue) {
                    selectedIndex = nextIndex
                }
            }
        )
    }

    private func centeredValue(for index: Int) -> Double {
        Double(index)
    }

    private var axisLabelPadding: CGFloat { 18 }

    @ViewBuilder
    private func axisLabelsLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        let plotFrame = proxy.plotAreaFrame
        let rect = geometry[plotFrame]
        ZStack(alignment: .topLeading) {
            ForEach(indexedPoints, id: \.point.id) { entry in
                if let xPosition = proxy.position(forX: centeredValue(for: entry.index)) {
                    Text(entry.point.displayLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(
                            x: rect.minX + xPosition,
                            y: rect.maxY + axisLabelPadding
                        )
                }
            }
        }
    }

    private func index(from value: Double) -> Int? {
        guard !indexedPoints.isEmpty else { return nil }
        let lowerBound = 0.0
        let upperBound = Double(indexedPoints.count - 1)
        let normalized = min(max(value, lowerBound), upperBound)
        let derived = Int(normalized.rounded())
        guard indexedPoints.indices.contains(derived) else { return nil }
        return derived
    }

    private func gradientColors(for valueMB: Double) -> [Color] {
        if usageAlertSettings.isEnabled,
           let thresholdMB = usageAlertSettings.dailyThresholdMB,
           valueMB > Double(thresholdMB) {
            return accentColor.palette(for: .usageAlertWarning).secondaryChartGradient
        }
        return accentColor.palette(for: .dailyChart).secondaryChartGradient
    }
}
