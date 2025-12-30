import Charts
import SwiftUI

struct BillingTabView: View {
  @ObservedObject var viewModel: AppViewModel
  let bill: BillSummaryResponse?
  let accentColors: AccentColorSettings
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var presentedEntry: BillSummaryResponse.BillEntry?

  private var isRegularWidth: Bool { horizontalSizeClass == .regular }

  var body: some View {
    GeometryReader { geometry in
      let isLandscape = geometry.size.width > geometry.size.height
      let useTwoColumn = isRegularWidth && isLandscape

      ScrollView {
        VStack(spacing: 20) {
          if let bill {
            if useTwoColumn {
              HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                  BillingHighlightCard(bill: bill) { entry in
                    presentedEntry = entry
                  }
                  BillingBarChart(bill: bill, accentColors: accentColors)
                }
                .frame(maxWidth: .infinity)

                BillSummaryList(bill: bill) { entry in
                  presentedEntry = entry
                }
                .padding()
                .background {
                  let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                  shape.fill(.thinMaterial)
                }
                .frame(maxWidth: 400)
              }
            } else {
              BillingHighlightCard(bill: bill) { entry in
                presentedEntry = entry
              }
              BillingBarChart(bill: bill, accentColors: accentColors)
              BillSummaryList(bill: bill) { entry in
                presentedEntry = entry
              }
              .padding()
              .background {
                let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                shape.fill(.thinMaterial)
              }
            }
          } else {
            EmptyStateView(text: "請求データがまだ取得されていません。")
          }
        }
        .padding()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(.systemGroupedBackground))
    }
    .sheet(item: $presentedEntry) { entry in
      if let bill {
        BillDetailSheet(viewModel: viewModel, bill: bill, initialEntry: entry)
      } else {
        EmptyView()
      }
    }
  }
}

struct BillingHighlightCard: View {
  let bill: BillSummaryResponse
  let onSelect: ((BillSummaryResponse.BillEntry) -> Void)?

  init(bill: BillSummaryResponse, onSelect: ((BillSummaryResponse.BillEntry) -> Void)? = nil) {
    self.bill = bill
    self.onSelect = onSelect
  }

  var body: some View {
    if let latest = bill.latestEntry {
      if let onSelect {
        Button {
          onSelect(latest)
        } label: {
          highlightCard(for: latest, isInteractive: true)
        }
        .buttonStyle(.plain)
      } else {
        highlightCard(for: latest, isInteractive: false)
      }
    } else {
      DashboardCard(title: "直近のご請求") {
        ChartPlaceholder(text: "請求データがありません")
      }
    }
  }

  @ViewBuilder
  private func highlightCard(for latest: BillSummaryResponse.BillEntry, isInteractive: Bool)
    -> some View
  {
    DashboardCard(
      title: "最新のご請求",
      subtitle: latest.isUnpaid == true ? "未払いのご請求があります" : "\(latest.formattedMonth)分のご請求はこちらです"
    ) {
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(latest.formattedAmount)
              .font(.system(size: 40, weight: .bold, design: .rounded))
              .foregroundStyle(latest.isUnpaid == true ? .red : .primary)
              .monospacedDigit()
          }
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 8) {
          if latest.isUnpaid == true {
            Label("未払い", systemImage: "exclamationmark.circle.fill")
              .font(.system(.caption, design: .rounded, weight: .bold))
              .foregroundStyle(.red)
              .padding(.horizontal, 10)
              .padding(.vertical, 4)
              .background(Color.red.opacity(0.1), in: Capsule())
          } else {
            Image(systemName: "creditcard.fill")
              .font(.system(size: 24))
              .foregroundStyle(.cyan.gradient)
              .padding(10)
              .background(Color.cyan.opacity(0.1), in: Circle())
          }

          if isInteractive {
            HStack(spacing: 4) {
              Text("詳細を見る")
                .font(.system(.caption2, design: .rounded, weight: .bold))
              Image(systemName: "chevron.right")
                .font(.system(.caption2, weight: .heavy))
            }
            .foregroundStyle(.cyan)
          }
        }
      }
    }
  }
}

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
          .annotation(position: .top) {
            Text(entry.point.value, format: .currency(code: "JPY").precision(.fractionLength(0)))
              .font(.caption2)
              .foregroundStyle(.secondary)
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
            }
          }
        }
        .chartYAxis {
          AxisMarks(position: .leading)
        }
        .chartYScale(domain: 0...yMaxValue)
        .chartXScale(domain: discreteDomain(forCount: indexedPoints.count))
        .chartOverlay { proxy in
          GeometryReader { geometry in
            axisLabelsLayer(proxy: proxy, geometry: geometry)
              .allowsHitTesting(false)
          }
        }
        .padding(.bottom, axisLabelPadding)
        .background {
          GeometryReader { proxy in
            Color.clear
              .onAppear {
                cardWidth = proxy.size.width
              }
              .onChange(of: proxy.size) { newSize in
                cardWidth = newSize.width
              }
          }
        }
        .frame(height: 260)
        .onAppear { triggerBarAnimation() }
        .onChange(of: animationToken) { _ in triggerBarAnimation() }
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

  private var axisLabelPadding: CGFloat { 18 }

  @ViewBuilder
  private func axisLabelsLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
    let plotFrame = proxy.plotAreaFrame
    let rect = geometry[plotFrame]
    ZStack(alignment: .topLeading) {
      ForEach(indexedPoints, id: \.point.id) { entry in
        if let xPosition = proxy.position(forX: centeredValue(for: entry.index)) {
          Text(billingAxisLabel(for: entry.point))
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

}

struct BillSummaryList: View {
  let bill: BillSummaryResponse
  let onSelect: ((BillSummaryResponse.BillEntry) -> Void)?
  private var entries: [BillSummaryResponse.BillEntry] {
    Array(bill.billList.prefix(12))
  }

  init(bill: BillSummaryResponse, onSelect: ((BillSummaryResponse.BillEntry) -> Void)? = nil) {
    self.bill = bill
    self.onSelect = onSelect
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("直近の請求金額")
        .font(.headline)

      ForEach(entries) { entry in
        row(for: entry)

        if entry.id != entries.last?.id {
          Divider()
        }
      }
    }
  }

  @ViewBuilder
  private func row(for entry: BillSummaryResponse.BillEntry) -> some View {
    if let onSelect {
      Button {
        onSelect(entry)
      } label: {
        rowContent(for: entry, isInteractive: true)
      }
      .buttonStyle(.plain)
    } else {
      rowContent(for: entry, isInteractive: false)
    }
  }

  @ViewBuilder
  private func rowContent(for entry: BillSummaryResponse.BillEntry, isInteractive: Bool)
    -> some View
  {
    HStack(spacing: 12) {
      let statusColor: Color = entry.isUnpaid == true ? .red : .blue

      Image(systemName: entry.isUnpaid == true ? "exclamationmark.circle.fill" : "doc.text.fill")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(statusColor)
        .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.formattedMonth)
          .font(.system(.subheadline, design: .rounded, weight: .bold))
          .foregroundStyle(.primary)

        if entry.isUnpaid == true {
          Text("未払い")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(.red)
        } else {
          Text("お支払い完了")
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      Text(entry.formattedAmount)
        .font(.system(.body, design: .rounded, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(entry.isUnpaid == true ? .red : .primary)

      if isInteractive {
        Image(systemName: "chevron.right")
          .font(.system(.caption2, weight: .bold))
          .foregroundStyle(.tertiary)
      }
    }
    .contentShape(Rectangle())
    .padding(.vertical, 8)
  }
}

struct BillDetailSheet: View {
  @ObservedObject var viewModel: AppViewModel
  private let entries: [BillSummaryResponse.BillEntry]
  @State private var selectedEntry: BillSummaryResponse.BillEntry
  @Environment(\.dismiss) private var dismiss
  @State private var loadState: LoadState = .loading

  private enum LoadState {
    case loading
    case loaded(BillDetailResponse)
    case failed(String)
  }

  init(
    viewModel: AppViewModel, bill: BillSummaryResponse, initialEntry: BillSummaryResponse.BillEntry
  ) {
    self.viewModel = viewModel
    self.entries = bill.billList
    _selectedEntry = State(initialValue: initialEntry)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        detailBackground
        detailContent
      }
      .navigationTitle("\(selectedEntry.formattedMonth)の明細")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          if entries.count > 1 {
            Menu {
              ForEach(entries) { entry in
                Button {
                  selectEntry(entry)
                } label: {
                  HStack {
                    Text(entry.formattedMonth)
                    if entry.id == selectedEntry.id {
                      Spacer()
                      Image(systemName: "checkmark")
                    }
                  }
                }
              }
            } label: {
              Label(selectedEntry.formattedMonth, systemImage: "calendar")
                .labelStyle(.titleAndIcon)
            }
            .accessibilityLabel("表示する月を選択")
          }
        }
      }
    }
    .task(id: selectedEntry.id) {
      await loadDetail(for: selectedEntry)
    }
  }

  @ViewBuilder
  private var detailBackground: some View {
    Color(.systemGroupedBackground)
      .ignoresSafeArea()
  }

  @ViewBuilder
  private var detailContent: some View {
    switch loadState {
    case .loading:
      ProgressView("読み込み中…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      VStack(spacing: 16) {
        Text("請求明細を取得できませんでした")
          .font(.headline)
        Text(message)
          .font(.subheadline)
          .multilineTextAlignment(.center)
        Button("再読み込み") {
          Task { await loadDetail(for: selectedEntry) }
        }
        .buttonStyle(.borderedProminent)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding()
    case .loaded(let detail):
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          BillDetailSummaryView(detail: detail)
          if !detail.taxBreakdowns.isEmpty {
            BillTaxBreakdownView(breakdowns: detail.taxBreakdowns)
          }
          ForEach(detail.sections) { section in
            BillDetailSectionView(section: section)
          }
        }
        .padding()
      }
    }
  }

  private func selectEntry(_ entry: BillSummaryResponse.BillEntry) {
    guard entry.id != selectedEntry.id else { return }
    selectedEntry = entry
    loadState = .loading
  }

  private func loadDetail(for entry: BillSummaryResponse.BillEntry) async {
    loadState = .loading
    let targetId = entry.id
    do {
      let detail = try await viewModel.fetchBillDetail(for: entry)
      guard targetId == selectedEntry.id else { return }
      loadState = .loaded(detail)
    } catch {
      guard targetId == selectedEntry.id else { return }
      loadState = .failed(error.localizedDescription)
    }
  }
}

struct BillDetailSummaryView: View {
  let detail: BillDetailResponse

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(detail.monthText)
        .font(.headline)
      Text(detail.totalAmountText)
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .foregroundStyle(.primary)
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background {
      if #available(iOS 26.0, *) {
        Color.clear
          .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      } else {
        Color.blue.opacity(0.08)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
    }
  }
}

struct BillTaxBreakdownView: View {
  let breakdowns: [BillDetailResponse.TaxBreakdown]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("税区分")
        .font(.headline)
      ForEach(breakdowns) { entry in
        HStack {
          VStack(alignment: .leading) {
            Text(entry.label)
            if let taxLabel = entry.taxLabel, !taxLabel.isEmpty {
              Text(taxLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          Spacer()
          VStack(alignment: .trailing) {
            Text(entry.amountText)
              .bold()
            if let taxAmount = entry.taxAmountText {
              Text(taxAmount)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        if entry.id != breakdowns.last?.id {
          Divider()
        }
      }
    }
    .padding()
    .background {
      Color(.secondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
  }
}

struct BillDetailSectionView: View {
  let section: BillDetailResponse.Section

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(section.title)
        .font(.headline)
      ForEach(section.items) { item in
        BillDetailItemRow(item: item)
        if item.id != section.items.last?.id {
          Divider()
        }
      }
      if let subtotal = section.subtotalText {
        HStack {
          Text("小計")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Spacer()
          Text(subtotal)
            .font(.headline)
            .monospacedDigit()
        }
      }
    }
    .padding()
    .background {
      Color(.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
  }
}

struct BillDetailItemRow: View {
  let item: BillDetailResponse.Item

  var body: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.subheadline.weight(.semibold))
        if let detail = item.detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
        if let quantity = item.quantityText {
          Text("数量 \(quantity)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let unit = item.unitPriceText {
          Text("単価 \(unit)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let amount = item.amountText {
          Text(amount)
            .font(.body.bold())
            .monospacedDigit()
        }
      }
    }
  }
}
