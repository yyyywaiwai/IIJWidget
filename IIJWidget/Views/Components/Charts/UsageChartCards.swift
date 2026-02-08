import Charts
import Foundation
import SwiftUI

struct MonthlyUsageChartCard: View {
  let services: [MonthlyUsageService]
  let accentColor: AccentColorSettings
  let usageAlertSettings: UsageAlertSettings
  let isRefreshing: Bool
  var animationTrigger: AnyHashable? = nil
  @State private var cardWidth: CGFloat = 0
  @State private var selectedIndex: Int?
  @State private var animateBars = false
  @State private var cachedPoints: [UsageChartPoint] = []
  @State private var cachedDisplayCount: Int = 0
  @State private var animationToken: String = ""

  private var currentDisplayCount: Int {
    cardWidth > 450 ? 12 : 7
  }
  private var displayCount: Int {
    cachedDisplayCount > 0 ? cachedDisplayCount : currentDisplayCount
  }
  private var points: [UsageChartPoint] {
    cachedPoints
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
    DashboardCard(title: "月別データ利用量", subtitle: "直近\(displayCount)か月 (GB)") {
      Group {
        if indexedPoints.isEmpty {
          if isRefreshing {
            LoadingStateView(text: "月別データを取得中…", minHeight: 160)
          } else {
            ChartPlaceholder(text: "まだデータがありません")
          }
        } else {
          chartContent
            .frame(height: 220)
        }
      }
      .onAppear {
        rebuildPoints()
        animateOnAppearIfNeeded()
      }
      .onChange(of: services) { _ in
        rebuildPoints()
      }
      .onChange(of: animationTrigger) { _ in
        triggerBarAnimation()
      }
      .onChange(of: animationToken) { _ in
        triggerBarAnimation()
      }
      .onDisappear {
        animateBars = false
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
          indexedPoints.indices.contains(index)
        {
          AxisGridLine(centered: true)
          AxisTick(centered: true)
          AxisValueLabel {
            Text(labelForIndex(index))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
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

          Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .simultaneousGesture(
              DragGesture(minimumDistance: 0)
                .onChanged { value in
                  guard !indexedPoints.isEmpty else { return }
                  if let newIndex = nearestIndex(
                    from: value.location,
                    proxy: proxy,
                    geometry: geometry)
                  {
                    selectedIndex = newIndex
                  }
                }
            )
        }
      }
    }
    .id(animationTrigger ?? AnyHashable("monthlyChart"))
    .padding(.bottom, axisLabelPadding)
    .background {
      GeometryReader { proxy in
        Color.clear
          .onAppear {
            cardWidth = proxy.size.width
          }
          .onChange(of: proxy.size) { newSize in
            cardWidth = newSize.width
            if currentDisplayCount != cachedDisplayCount {
              rebuildPoints()
            }
          }
      }
    }
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

  private func labelForIndex(_ index: Int) -> String {
    guard indexedPoints.indices.contains(index) else { return "" }
    return indexedPoints[index].point.displayLabel
  }

  private func rebuildPoints() {
    let targetCount = currentDisplayCount
    let servicesSnapshot = services
    DispatchQueue.global(qos: .userInitiated).async {
      let nextPoints = Array(monthlyChartPoints(from: servicesSnapshot).suffix(targetCount))
      let token = nextPoints.map { "\($0.id)-\($0.value)" }.joined(separator: "|")
      DispatchQueue.main.async {
        if cachedDisplayCount == targetCount && animationToken == token {
          return
        }
        cachedPoints = nextPoints
        cachedDisplayCount = targetCount
        selectedIndex = nextPoints.isEmpty ? nil : nextPoints.count - 1
        animationToken = token
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
      (valueGB * 1000) > Double(thresholdMB)
    {
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

  private func animateOnAppearIfNeeded() {
    // TabView keeps child views alive; when switching tabs, `onDisappear` runs and we reset
    // `animateBars` to false. If the underlying data didn't change, `rebuildPoints()` is a no-op
    // and no animation trigger fires, leaving the bars stuck at 0. Ensure we restore the bars.
    guard !indexedPoints.isEmpty, !animateBars else { return }
    triggerBarAnimation()
  }

  @ViewBuilder
  private func selectionCalloutLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
    let plotFrame = proxy.plotAreaFrame
    let rect = geometry[plotFrame]

    if let selectedIndex,
      let selectedPoint,
      rect != .null,
      let xPosition = proxy.position(forX: centeredValue(for: selectedIndex))
    {
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

  private func nearestIndex(from location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy)
    -> Int?
  {
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
  let isRefreshing: Bool
  var animationTrigger: AnyHashable? = nil
  @State private var cardWidth: CGFloat = 0
  @State private var selectedIndex: Int?
  @State private var animateBars = false
  @State private var cachedPoints: [UsageChartPoint] = []
  @State private var cachedDisplayCount: Int = 0
  @State private var animationToken: String = ""

  private var currentDisplayCount: Int {
    cardWidth > 450 ? 14 : 7
  }

  private var displayCount: Int {
    cachedDisplayCount > 0 ? cachedDisplayCount : currentDisplayCount
  }

  private var visiblePoints: [UsageChartPoint] {
    cachedPoints
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
    DashboardCard(title: "日別データ利用量", subtitle: "直近\(displayCount)日 (MB)") {
      Group {
        if indexedPoints.isEmpty {
          if isRefreshing {
            LoadingStateView(text: "日別データを取得中…", minHeight: 160)
          } else {
            ChartPlaceholder(text: "まだデータがありません")
          }
        } else {
          chartContent
            .frame(height: 220)
        }
      }
      .onAppear {
        rebuildPoints()
        animateOnAppearIfNeeded()
      }
      .onChange(of: services) { _ in
        rebuildPoints()
      }
      .onChange(of: animationTrigger) { _ in
        triggerBarAnimation()
      }
      .onChange(of: animationToken) { _ in
        triggerBarAnimation()
      }
      .onDisappear {
        animateBars = false
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
          indexedPoints.indices.contains(index)
        {
          AxisGridLine(centered: true)
          AxisTick(centered: true)
          AxisValueLabel {
            Text(labelForIndex(index))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
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

          Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .simultaneousGesture(
              DragGesture(minimumDistance: 0)
                .onChanged { value in
                  guard !indexedPoints.isEmpty else { return }
                  if let newIndex = nearestIndex(
                    from: value.location,
                    proxy: proxy,
                    geometry: geometry)
                  {
                    selectedIndex = newIndex
                  }
                }
            )
        }
      }
    }
    .id(animationTrigger ?? AnyHashable("dailyChart"))
    .padding(.bottom, axisLabelPadding)
    .background {
      GeometryReader { proxy in
        Color.clear
          .onAppear {
            cardWidth = proxy.size.width
          }
          .onChange(of: proxy.size) { newSize in
            cardWidth = newSize.width
            if currentDisplayCount != cachedDisplayCount {
              rebuildPoints()
            }
          }
      }
    }
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

  private func labelForIndex(_ index: Int) -> String {
    guard indexedPoints.indices.contains(index) else { return "" }
    return indexedPoints[index].point.displayLabel
  }

  private func rebuildPoints() {
    let targetCount = currentDisplayCount
    let servicesSnapshot = services
    DispatchQueue.global(qos: .userInitiated).async {
      let nextPoints = Array(dailyChartPoints(from: servicesSnapshot).suffix(targetCount))
      let token = nextPoints.map { "\($0.id)-\($0.value)" }.joined(separator: "|")
      DispatchQueue.main.async {
        if cachedDisplayCount == targetCount && animationToken == token {
          return
        }
        cachedPoints = nextPoints
        cachedDisplayCount = targetCount
        selectedIndex = nextPoints.isEmpty ? nil : nextPoints.count - 1
        animationToken = token
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
      valueMB > Double(thresholdMB)
    {
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

  private func animateOnAppearIfNeeded() {
    // See MonthlyUsageChartCard.animateOnAppearIfNeeded().
    guard !indexedPoints.isEmpty, !animateBars else { return }
    triggerBarAnimation()
  }

  @ViewBuilder
  private func selectionCalloutLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
    let plotFrame = proxy.plotAreaFrame
    let rect = geometry[plotFrame]

    if let selectedIndex,
      let selectedPoint,
      rect != .null,
      let xPosition = proxy.position(forX: centeredValue(for: selectedIndex))
    {
      let barTopY = proxy.position(forY: selectedPoint.value) ?? 0
      let calloutHeight: CGFloat = 44
      let gap: CGFloat = 8
      let candidateY = rect.minY + barTopY - (calloutHeight + gap)
      let clampedY = max(rect.minY - 12, candidateY)

      ChartCallout(
        title: selectedPoint.displayLabel, valueText: String(format: "%.0fMB", selectedPoint.value)
      )
      .position(
        x: rect.minX + xPosition,
        y: clampedY
      )
    } else {
      EmptyView()
    }
  }

  private func nearestIndex(from location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy)
    -> Int?
  {
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
