import SwiftUI
import Charts

struct MonthlyUsageChartCard: View {
    let services: [MonthlyUsageService]
    let accentColor: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    var animationTrigger: AnyHashable? = nil
    @State private var selectedIndex: Int?
    @State private var animateBars = false
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

    private var yMaxValue: Double {
        let maxValue = indexedPoints.map { $0.point.value }.max() ?? 1
        return max(1, maxValue * 1.08)
    }

    var body: some View {
        DashboardCard(title: "月別データ利用量", subtitle: "直近7か月 (GB)") {
            if indexedPoints.isEmpty {
                ChartPlaceholder(text: "まだデータがありません")
            } else {
                chartContent
                    .frame(height: 220)
                    .onAppear {
                        selectedIndex = defaultSelectionIndex
                        triggerBarAnimation()
                    }
                    .onChange(of: services) { _ in
                        selectedIndex = defaultSelectionIndex
                        triggerBarAnimation()
                    }
                    .onChange(of: animationTrigger) { _ in
                        triggerBarAnimation()
                    }
                    .onDisappear {
                        animateBars = false
                    }
            }
        }
    }

    private var chartContent: some View {
        Chart {
            ForEach(indexedPoints, id: \.point.id) { entry in
                BarMark(
                    x: .value("月インデックス", centeredValue(for: entry.index)),
                    y: .value("合計(GB)", animatedValue(entry.point.value)),
                    width: .fixed(barWidth)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors(for: entry.point.value),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(selectedIndex == entry.index ? 1.0 : 0.85)
            }

            if let selectedIndex, let selectedPoint {
                RuleMark(
                    x: .value("選択", centeredValue(for: selectedIndex)),
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
            AxisMarks(values: axisPositions) { value in
                if let doubleValue = value.as(Double.self),
                   let index = index(from: doubleValue),
                   indexedPoints.indices.contains(index) {
                    AxisGridLine(centered: true)
                    AxisTick(centered: true)
                }
            }
        }
        .chartYScale(domain: 0...yMaxValue)
        .chartXScale(domain: discreteDomain(forCount: indexedPoints.count))
        .chartXSelection(value: chartSelectionBinding)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    selectionCalloutLayer(proxy: proxy, geometry: geometry)
                        .allowsHitTesting(false)

                    axisLabelsLayer(proxy: proxy, geometry: geometry)
                        .allowsHitTesting(false)

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard !indexedPoints.isEmpty else { return }
                                    if let newIndex = nearestIndex(from: value.location,
                                                                  proxy: proxy,
                                                                  geometry: geometry) {
                                        selectedIndex = newIndex
                                    }
                                }
                        )
                }
            }
        }
        .id(animationTrigger ?? AnyHashable("monthlyChart"))
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

    private func gradientColors(for valueGB: Double) -> [Color] {
        if usageAlertSettings.isEnabled,
           let thresholdMB = usageAlertSettings.monthlyThresholdMB,
           (valueGB * 1000) > Double(thresholdMB) {
            return accentColor.palette(for: .usageAlertWarning).secondaryChartGradient
        }
        return accentColor.palette(for: .monthlyChart).secondaryChartGradient
    }

    private func animatedValue(_ value: Double) -> Double {
        animateBars ? value : 0
    }

    private func triggerBarAnimation() {
        animateBars = false
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.15)) {
                animateBars = true
            }
        }
    }

    @ViewBuilder
    private func selectionCalloutLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        let plotFrame = proxy.plotAreaFrame
        let rect = geometry[plotFrame]

        if let selectedIndex,
           let selectedPoint,
           rect != .null,
           let xPosition = proxy.position(forX: centeredValue(for: selectedIndex)) {
            let barTopY = proxy.position(forY: selectedPoint.value) ?? 0
            let calloutHeight: CGFloat = 44
            let gap: CGFloat = 8
            let candidateY = rect.minY + barTopY - (calloutHeight + gap)
            let clampedY = max(rect.minY - 12, candidateY)

            ChartCallout(
                title: selectedPoint.displayLabel,
                valueText: String(format: "%.1fGB", selectedPoint.value)
            )
            .position(
                x: rect.minX + xPosition,
                y: clampedY
            )
        } else {
            EmptyView()
        }
    }

    private func nearestIndex(from location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Int? {
        let plotFrame = proxy.plotAreaFrame
        let rect = geometry[plotFrame]
        guard rect != .null else { return nil }

        let relativeX = location.x - rect.minX
        guard relativeX >= 0, relativeX <= rect.width else { return nil }

        var closest: (index: Int, distance: CGFloat)?

        for entry in indexedPoints {
            guard let position = proxy.position(forX: centeredValue(for: entry.index)) else { continue }
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

struct DailyUsageChartCard: View {
    let services: [DailyUsageService]
    let accentColor: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    var animationTrigger: AnyHashable? = nil
    @State private var selectedIndex: Int?
    @State private var animateBars = false

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

    private var yMaxValue: Double {
        let maxValue = indexedPoints.map { $0.point.value }.max() ?? 1
        return max(1, maxValue * 1.08)
    }

    var body: some View {
        DashboardCard(title: "日別データ利用量", subtitle: "履歴 (MB)") {
            if indexedPoints.isEmpty {
                ChartPlaceholder(text: "まだデータがありません")
            } else {
                chartContent
                    .frame(height: 220)
                    .onAppear {
                        selectedIndex = defaultSelectionIndex
                        triggerBarAnimation()
                    }
                    .onChange(of: services) { _ in
                        selectedIndex = defaultSelectionIndex
                        triggerBarAnimation()
                    }
                    .onChange(of: animationTrigger) { _ in
                        triggerBarAnimation()
                    }
                    .onDisappear {
                        animateBars = false
                    }
            }
        }
    }

    private var chartContent: some View {
        Chart {
            ForEach(indexedPoints, id: \.point.id) { entry in
                BarMark(
                    x: .value("日インデックス", centeredValue(for: entry.index)),
                    y: .value("合計(MB)", animatedValue(entry.point.value)),
                    width: .fixed(barWidth)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors(for: entry.point.value),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .opacity(selectedIndex == entry.index ? 1.0 : 0.85)
            }

            if let selectedIndex, let selectedPoint {
                RuleMark(
                    x: .value("選択", centeredValue(for: selectedIndex)),
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
            AxisMarks(values: axisPositions) { value in
                if let doubleValue = value.as(Double.self),
                   let index = index(from: doubleValue),
                   indexedPoints.indices.contains(index) {
                    AxisGridLine(centered: true)
                    AxisTick(centered: true)
                }
            }
        }
        .chartYScale(domain: 0...yMaxValue)
        .chartXScale(domain: discreteDomain(forCount: indexedPoints.count))
        .chartXSelection(value: chartSelectionBinding)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    selectionCalloutLayer(proxy: proxy, geometry: geometry)
                        .allowsHitTesting(false)

                    axisLabelsLayer(proxy: proxy, geometry: geometry)
                        .allowsHitTesting(false)

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard !indexedPoints.isEmpty else { return }
                                    if let newIndex = nearestIndex(from: value.location,
                                                                  proxy: proxy,
                                                                  geometry: geometry) {
                                        selectedIndex = newIndex
                                    }
                                }
                        )
                }
            }
        }
        .id(animationTrigger ?? AnyHashable("dailyChart"))
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

    private func animatedValue(_ value: Double) -> Double {
        animateBars ? value : 0
    }

    private func triggerBarAnimation() {
        animateBars = false
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.15)) {
                animateBars = true
            }
        }
    }

    @ViewBuilder
    private func selectionCalloutLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        let plotFrame = proxy.plotAreaFrame
        let rect = geometry[plotFrame]

        if let selectedIndex,
           let selectedPoint,
           rect != .null,
           let xPosition = proxy.position(forX: centeredValue(for: selectedIndex)) {
            let barTopY = proxy.position(forY: selectedPoint.value) ?? 0
            let calloutHeight: CGFloat = 44
            let gap: CGFloat = 8
            let candidateY = rect.minY + barTopY - (calloutHeight + gap)
            let clampedY = max(rect.minY - 12, candidateY)

            ChartCallout(title: selectedPoint.displayLabel, valueText: String(format: "%.0fMB", selectedPoint.value))
                .position(
                    x: rect.minX + xPosition,
                    y: clampedY
                )
        } else {
            EmptyView()
        }
    }

    private func nearestIndex(from location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Int? {
        let plotFrame = proxy.plotAreaFrame
        let rect = geometry[plotFrame]
        guard rect != .null else { return nil }

        let relativeX = location.x - rect.minX
        guard relativeX >= 0, relativeX <= rect.width else { return nil }

        var closest: (index: Int, distance: CGFloat)?

        for entry in indexedPoints {
            guard let position = proxy.position(forX: centeredValue(for: entry.index)) else { continue }
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
