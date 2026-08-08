import Charts
import SwiftUI

struct BillingTabView: View {
  @ObservedObject var viewModel: AppViewModel
  let bill: BillSummaryResponse?
  let accentColors: AccentColorSettings
  let showsBillingChart: Bool
  let refresh: () async -> Void
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var presentedEntry: BillSummaryResponse.BillEntry?

  private var isRegularWidth: Bool { horizontalSizeClass == .regular }

  var body: some View {
    GeometryReader { geometry in
      let isLandscape = geometry.size.width > geometry.size.height
      let useTwoColumn = isRegularWidth && isLandscape

      ScrollView {
        VStack(spacing: AppSpacing.xl) {
          if let bill {
            if useTwoColumn {
              HStack(alignment: .top, spacing: AppSpacing.xl) {
                VStack(spacing: AppSpacing.xl) {
                  BillingHighlightCard(bill: bill, accentColors: accentColors) { entry in
                    presentedEntry = entry
                  }
                  if showsBillingChart {
                    BillingBarChart(bill: bill, accentColors: accentColors)
                  }
                }
                .frame(maxWidth: .infinity)

                BillSummaryList(bill: bill, accentColors: accentColors) { entry in
                  presentedEntry = entry
                }
                .padding(AppSpacing.lg)
                .cardSurface(cornerRadius: AppRadius.lg)
                .frame(maxWidth: 400)
              }
            } else {
              BillingHighlightCard(bill: bill, accentColors: accentColors) { entry in
                presentedEntry = entry
              }
              if showsBillingChart {
                BillingBarChart(bill: bill, accentColors: accentColors)
              }
              BillSummaryList(bill: bill, accentColors: accentColors) { entry in
                presentedEntry = entry
              }
              .padding(AppSpacing.lg)
              .cardSurface(cornerRadius: AppRadius.lg)
            }
          } else {
            EmptyStateView(
              title: "請求データがありません",
              message: "請求データがまだ取得されていません。下に引っ張るか、「最新取得」をタップしてください。",
              systemImage: "yensign.circle"
            ) {
              Button("最新取得") {
                Task { await refresh() }
              }
              .buttonStyle(.borderedProminent)
            }
          }
        }
        .padding(AppSpacing.lg)
      }
      .refreshable { await refresh() }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(.systemGroupedBackground))
    }
    .sheet(item: $presentedEntry) { entry in
      if let bill {
        BillDetailSheet(viewModel: viewModel, bill: bill, initialEntry: entry)
          .presentationDetents([.large, .medium])
          .presentationDragIndicator(.visible)
      } else {
        EmptyView()
      }
    }
  }
}

struct BillingHighlightCard: View {
  let bill: BillSummaryResponse
  let accentColors: AccentColorSettings
  let onSelect: ((BillSummaryResponse.BillEntry) -> Void)?

  init(
    bill: BillSummaryResponse,
    accentColors: AccentColorSettings,
    onSelect: ((BillSummaryResponse.BillEntry) -> Void)? = nil
  ) {
    self.bill = bill
    self.accentColors = accentColors
    self.onSelect = onSelect
  }

  private var accentColor: Color {
    accentColors.palette(for: .billingChart).previewSymbolColor
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
        .accessibilityHint("タップすると請求明細を開きます")
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
    let isUnpaid = latest.isUnpaid == true
    DashboardCard(
      title: "最新のご請求",
      subtitle: isUnpaid ? "未払いのご請求があります" : "\(latest.formattedMonth)分のご請求はこちらです"
    ) {
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
          Text(latest.formattedAmount)
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(isUnpaid ? Color.red : Color.primary)
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(latest.formattedMonth)分のご請求")
        .accessibilityValue(isUnpaid ? "\(latest.formattedAmount)、未払い" : latest.formattedAmount)

        Spacer(minLength: AppSpacing.md)

        VStack(alignment: .trailing, spacing: AppSpacing.sm) {
          if isUnpaid {
            Label("未払い", systemImage: "exclamationmark.circle.fill")
              .font(.system(.caption, design: .rounded, weight: .bold))
              .foregroundStyle(.red)
              .padding(.horizontal, AppSpacing.sm + 2)
              .padding(.vertical, AppSpacing.xs)
              .background(Color.red.opacity(0.1), in: Capsule())
              .accessibilityHidden(true)
          } else {
            Image(systemName: "creditcard.fill")
              .font(.system(size: 24))
              .foregroundStyle(accentColor.gradient)
              .padding(AppSpacing.sm + 2)
              .background(accentColor.opacity(0.1), in: Circle())
              .accessibilityHidden(true)
          }

          if isInteractive {
            HStack(spacing: AppSpacing.xs) {
              Text("詳細を見る")
                .font(.system(.caption2, design: .rounded, weight: .bold))
              Image(systemName: "chevron.right")
                .font(.system(.caption2, weight: .heavy))
            }
            .foregroundStyle(accentColor)
            .accessibilityHidden(true)
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
          .accessibilityLabel(billingAxisLabel(for: entry.point))
          .accessibilityValue(
            entry.point.isUnpaid
              ? "\(currencyText(entry.point.value))、未払い" : currencyText(entry.point.value)
          )
          .annotation(position: .top) {
            HStack(spacing: 2) {
              // 未払いは色に加えて記号でも示す。
              if entry.point.isUnpaid {
                Image(systemName: "exclamationmark.circle.fill")
                  .font(.system(size: 8))
                  .foregroundStyle(.red)
              }
              Text(entry.point.value, format: .currency(code: "JPY").precision(.fractionLength(0)))
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

struct BillSummaryList: View {
  let bill: BillSummaryResponse
  let accentColors: AccentColorSettings
  let onSelect: ((BillSummaryResponse.BillEntry) -> Void)?
  private var entries: [BillSummaryResponse.BillEntry] {
    Array(bill.billList.prefix(12))
  }

  init(
    bill: BillSummaryResponse,
    accentColors: AccentColorSettings,
    onSelect: ((BillSummaryResponse.BillEntry) -> Void)? = nil
  ) {
    self.bill = bill
    self.accentColors = accentColors
    self.onSelect = onSelect
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
      Text("直近の請求金額")
        .font(.system(.headline, design: .rounded, weight: .bold))
        .accessibilityAddTraits(.isHeader)

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
      .accessibilityHint("タップすると明細を開きます")
    } else {
      rowContent(for: entry, isInteractive: false)
    }
  }

  @ViewBuilder
  private func rowContent(for entry: BillSummaryResponse.BillEntry, isInteractive: Bool)
    -> some View
  {
    let isUnpaid = entry.isUnpaid == true
    HStack(spacing: AppSpacing.md) {
      let statusColor: Color =
        isUnpaid ? .red : accentColors.palette(for: .billingChart).previewSymbolColor

      Image(systemName: isUnpaid ? "exclamationmark.circle.fill" : "doc.text.fill")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(statusColor)
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.formattedMonth)
          .font(.system(.subheadline, design: .rounded, weight: .bold))
          .foregroundStyle(.primary)

        if isUnpaid {
          Text("未払い")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(.red)
        } else {
          Text("お支払い完了")
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: AppSpacing.sm)

      Text(entry.formattedAmount)
        .font(.system(.body, design: .rounded, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(isUnpaid ? Color.red : Color.primary)

      if isInteractive {
        Image(systemName: "chevron.right")
          .font(.system(.caption2, weight: .bold))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
    }
    .contentShape(Rectangle())
    .padding(.vertical, AppSpacing.sm)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(entry.formattedMonth)
    .accessibilityValue(
      isUnpaid ? "\(entry.formattedAmount)、未払い" : "\(entry.formattedAmount)、お支払い完了")
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
      // 単なるスピナーではなく最終的なレイアウトを模したスケルトンを出し、
      // 読み込み完了時のガタつきを抑える。
      ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
          BillDetailSkeletonCard(lineWidths: [0.35, 0.6])
          BillDetailSkeletonCard(lineWidths: [0.3, 0.9, 0.75])
          BillDetailSkeletonCard(lineWidths: [0.3, 0.85, 0.7, 0.8])
        }
        .padding()
      }
      .disabled(true)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("請求明細を読み込み中")
    case .failed(let message):
      ContentUnavailableView {
        Label("請求明細を取得できませんでした", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("再読み込み") {
          Task { await loadDetail(for: selectedEntry) }
        }
        .buttonStyle(.borderedProminent)
      }
    case .loaded(let detail):
      ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
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
      // シートを閉じたり別の月へ切り替えると .task がキャンセルされる。
      // これは失敗ではないのでエラー表示せずそのまま抜ける。
      guard !TaskCancellation.isCancellation(error) else { return }
      loadState = .failed(error.localizedDescription)
    }
  }
}

/// 明細読み込み中に表示するプレースホルダーカード。
private struct BillDetailSkeletonCard: View {
  /// 各行の幅を親に対する比率で指定する。
  let lineWidths: [CGFloat]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isPulsing = false

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
      ForEach(Array(lineWidths.enumerated()), id: \.offset) { _, ratio in
        GeometryReader { proxy in
          Capsule()
            .fill(Color.primary.opacity(0.08))
            .frame(width: proxy.size.width * ratio, height: 14)
        }
        .frame(height: 14)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(cornerRadius: AppRadius.md, elevation: .flat)
    .opacity(isPulsing ? 0.55 : 1)
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
        isPulsing = true
      }
    }
  }
}

struct BillDetailSummaryView: View {
  let detail: BillDetailResponse

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      Text(detail.monthText)
        .font(.system(.headline, design: .rounded, weight: .bold))
      Text(detail.totalAmountText)
        .font(.system(.largeTitle, design: .rounded, weight: .bold))
        .foregroundStyle(.primary)
        .monospacedDigit()
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .cardSurface(cornerRadius: AppRadius.md)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(detail.monthText)の合計")
    .accessibilityValue(detail.totalAmountText)
  }
}

struct BillTaxBreakdownView: View {
  let breakdowns: [BillDetailResponse.TaxBreakdown]

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      Text("税区分")
        .font(.system(.headline, design: .rounded, weight: .bold))
        .accessibilityAddTraits(.isHeader)
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
          Spacer(minLength: AppSpacing.sm)
          VStack(alignment: .trailing) {
            Text(entry.amountText)
              .bold()
              .monospacedDigit()
            if let taxAmount = entry.taxAmountText {
              Text(taxAmount)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
          }
        }
        .accessibilityElement(children: .combine)
        if entry.id != breakdowns.last?.id {
          Divider()
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(cornerRadius: AppRadius.md, material: .ultraThinMaterial, elevation: .flat)
  }
}

struct BillDetailSectionView: View {
  let section: BillDetailResponse.Section

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
      Text(section.title)
        .font(.system(.headline, design: .rounded, weight: .bold))
        .accessibilityAddTraits(.isHeader)
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
          Spacer(minLength: AppSpacing.sm)
          Text(subtotal)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(cornerRadius: AppRadius.md, material: .regularMaterial)
  }
}

struct BillDetailItemRow: View {
  let item: BillDetailResponse.Item

  var body: some View {
    HStack(alignment: .top, spacing: AppSpacing.md) {
      VStack(alignment: .leading, spacing: AppSpacing.xs) {
        Text(item.title)
          .font(.subheadline.weight(.semibold))
        if let detail = item.detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: AppSpacing.sm)
      VStack(alignment: .trailing, spacing: AppSpacing.xs) {
        if let quantity = item.quantityText {
          Text("数量 \(quantity)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        if let unit = item.unitPriceText {
          Text("単価 \(unit)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        if let amount = item.amountText {
          Text(amount)
            .font(.body.bold())
            .monospacedDigit()
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}
