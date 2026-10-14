import Charts
import SwiftUI

struct BillingBarChart: View {
    let bill: BillSummaryResponse
    let accentColors: AccentColorSettings
    @State private var cardWidth: CGFloat = 0
    @State private var animateBars = false

    private var displayCount: Int {
        cardWidth > 450 ? 12 : 7
    }
    private var points: [BillChartPoint] {
        Array(billingChartPoints(from: bill).suffix(displayCount))
    }
    private var indexedPoints: [(index: Int, point: BillChartPoint)] {
        points.enumerated().map { (index: $0.offset, point: $0.element) }
    }

    private var yMaxValue: Double {
        let maxValue = indexedPoints.map { $0.point.value }.max() ?? 1
        return max(1, maxValue * 1.08)
    }

    private var animationToken: String {
        indexedPoints.map { "\($0.point.id)-\($0.point.value)" }.joined(separator: "|")
    }

    var body: some View {
        DashboardCard(title: "請求額の推移", subtitle: "直近\(displayCount)か月") {
            if indexedPoints.isEmpty {
                ChartPlaceholder(text: "データが不足しています")
            } else {
                Chart(indexedPoints, id: \.point.id) { entry in
                    BarMark(
                        x: .value("月インデックス", centeredValue(for: entry.index)),
                        y: .value("金額(¥)", animatedValue(entry.point.value)),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(entry.point.isUnpaid ? unpaidGradient : paidGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityLabel(billingAxisLabel(for: entry.point))
                    .accessibilityValue(
                        entry.point.isUnpaid
                            ? "\(currencyText(entry.point.value))、未払い"
                            : currencyText(entry.point.value)
                    )
                    .annotation(position: .top) {
                        HStack(spacing: 2) {
                            // 未払いは色に加えて記号でも示す。
                            if entry.point.isUnpaid {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.red)
                            }
                            Text(
                                entry.point.value,
                                format: .currency(code: "JPY").precision(.fractionLength(0))
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .accessibilityHidden(true)
                    }
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
                                Text(billingAxisLabel(for: indexedPoints[index].point))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYScale(domain: 0...yMaxValue)
                .chartXScale(domain: discreteDomain(forCount: indexedPoints.count))
                .padding(.bottom, axisLabelPadding)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                cardWidth = proxy.size.width
                            }
                            .onChange(of: proxy.size) { _, newSize in
                                cardWidth = newSize.width
                            }
                    }
                }
                .frame(height: 260)
                .onAppear { triggerBarAnimation() }
                .onChange(of: animationToken) { _, _ in triggerBarAnimation() }
                .onDisappear { animateBars = false }
            }
        }
    }

    private var paidGradient: LinearGradient {
        let colors = accentColors.palette(for: .billingChart).secondaryChartGradient
        return LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top)
    }

    private var unpaidGradient: LinearGradient {
        let base = accentColors.palette(for: .billingChart).secondaryChartGradient
        let tinted: [Color] = [
            base.first?.opacity(0.6) ?? .orange.opacity(0.7),
            Color.red.opacity(0.9),
        ]
        return LinearGradient(colors: tinted, startPoint: .bottom, endPoint: .top)
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

    private func centeredValue(for index: Int) -> Double {
        Double(index)
    }

    private func currencyText(_ value: Double) -> String {
        value.formatted(.currency(code: "JPY").precision(.fractionLength(0)))
    }

    private var axisLabelPadding: CGFloat { 18 }

    private func index(from value: Double) -> Int? {
        guard !indexedPoints.isEmpty else { return nil }
        let lowerBound = 0.0
        let upperBound = Double(indexedPoints.count - 1)
        let normalized = min(max(value, lowerBound), upperBound)
        let derived = Int(normalized.rounded())
        guard indexedPoints.indices.contains(derived) else { return nil }
        return derived
    }

    private func animatedValue(_ value: Double) -> Double {
        animateBars ? value : 0
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
