import SwiftUI

struct BillDetailSheet: View {
    let viewModel: AppViewModel
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
        viewModel: AppViewModel, bill: BillSummaryResponse,
        initialEntry: BillSummaryResponse.BillEntry
    ) {
        self.viewModel = viewModel
        self.entries = bill.billList
        // 開いた時の月を初期値にし、その後の月選択はシートが所有する。
        _selectedEntry = State(initialValue: initialEntry)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
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
    private var detailContent: some View {
        switch loadState {
        case .loading:
            BillDetailLoadingView()
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
            BillDetailContentView(detail: detail)
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
            guard !Task.isCancelled, targetId == selectedEntry.id else { return }
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
