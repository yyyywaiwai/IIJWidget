import SwiftUI
import Charts

struct BillingTabView: View {
    @ObservedObject var viewModel: AppViewModel
    let bill: BillSummaryResponse?
    @State private var presentedEntry: BillSummaryResponse.BillEntry?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let bill {
                    BillingHighlightCard(bill: bill)
                    if let latest = bill.latestEntry {
                        Button {
                            presentedEntry = latest
                        } label: {
                            Label("最新の請求明細を表示", systemImage: "doc.text.magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    BillingBarChart(bill: bill)
                    BillSummaryList(bill: bill) { entry in
                        presentedEntry = entry
                    }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    EmptyStateView(text: "請求データがまだ取得されていません。")
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
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

    var body: some View {
        if let latest = bill.latestEntry {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(latest.formattedMonth)のご請求")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))

                Text(latest.formattedAmount)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)

                if latest.isUnpaid == true {
                    Text("未払い")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.15), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.indigo, Color.blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24)
            )
        } else {
            DashboardCard(title: "直近の請求額") {
                ChartPlaceholder(text: "請求データがありません")
            }
        }
    }
}

struct BillingBarChart: View {
    let bill: BillSummaryResponse
    private var points: [BillChartPoint] {
        billingChartPoints(from: bill)
    }
    private var indexedPoints: [(index: Int, point: BillChartPoint)] {
        points.enumerated().map { (index: $0.offset, point: $0.element) }
    }

    var body: some View {
        DashboardCard(title: "請求額の推移", subtitle: "直近6か月") {
            if indexedPoints.isEmpty {
                ChartPlaceholder(text: "データが不足しています")
            } else {
                Chart(indexedPoints, id: \.point.id) { entry in
                    BarMark(
                        x: .value("月インデックス", centeredValue(for: entry.index)),
                        y: .value("金額(¥)", entry.point.value),
                        width: .fixed(36)
                    )
                    .foregroundStyle(entry.point.isUnpaid ? unpaidGradient : paidGradient)
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
                           indexedPoints.indices.contains(index) {
                            AxisGridLine(centered: true)
                            AxisTick(centered: true)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXScale(domain: discreteDomain(forCount: indexedPoints.count))
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        axisLabelsLayer(proxy: proxy, geometry: geometry)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.bottom, axisLabelPadding)
                .frame(height: 260)
            }
        }
    }

    private var paidGradient: LinearGradient {
        LinearGradient(colors: [Color.blue, Color.mint], startPoint: .bottom, endPoint: .top)
    }

    private var unpaidGradient: LinearGradient {
        LinearGradient(colors: [Color.orange, Color.red], startPoint: .bottom, endPoint: .top)
    }

    private var axisPositions: [Double] {
        indexedPoints.map { centeredValue(for: $0.index) }
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
    private func rowContent(for entry: BillSummaryResponse.BillEntry, isInteractive: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.formattedMonth)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if entry.isUnpaid == true {
                    Text("未払い")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Text(entry.formattedAmount)
                .font(.body.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
            if isInteractive {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
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

    init(viewModel: AppViewModel, bill: BillSummaryResponse, initialEntry: BillSummaryResponse.BillEntry) {
        self.viewModel = viewModel
        self.entries = bill.billList
        _selectedEntry = State(initialValue: initialEntry)
    }

    var body: some View {
        NavigationStack {
            Group {
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
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
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
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
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
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
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

