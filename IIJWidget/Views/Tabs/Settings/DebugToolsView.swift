import Combine
import SwiftUI

struct DebugToolsView: View {
    @StateObject private var viewModel = DebugToolsViewModel()

    var body: some View {
        List {
            Section(header: Text("ウィジェットキャッシュ")) {
                cacheRow(
                    title: "AggregatePayload",
                    subtitle: viewModel.aggregatePayload?.fetchedAt,
                    text: viewModel.aggregatePayloadText
                )

                cacheRow(
                    title: "WidgetSnapshot",
                    subtitle: viewModel.widgetSnapshot?.fetchedAt,
                    text: viewModel.widgetSnapshotText
                )

                Button(role: .destructive) {
                    viewModel.showCacheClearConfirmation = true
                } label: {
                    Label("キャッシュを削除", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }

            Section(header: Text("レスポンス")) {
                if viewModel.responses.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("まだ記録がありません")
                            .font(.subheadline)
                        Text("最新取得を実行すると API / スクレイピングレスポンスがここに保存されます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } else {
                    ForEach(viewModel.responses) { record in
                        NavigationLink {
                            DebugResponseDetailView(record: record)
                        } label: {
                            responseRow(record)
                        }
                    }
                }

                Button(role: .destructive) {
                    viewModel.showResponseClearConfirmation = true
                } label: {
                    Label("レスポンスログをクリア", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .disabled(viewModel.responses.isEmpty)
            }

            Section(header: Text("セッションCookie")) {
                if viewModel.cookies.isEmpty {
                    Text("保存されている Cookie はありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.cookies, id: \.debugIdentifier) { cookie in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(cookie.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(cookie.domain)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let expires = cookie.expiresDate {
                                Text("有効期限: \(DebugToolsViewModel.dateFormatter.string(from: expires))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(cookie.value)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(nil)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("デバッグツール")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("再読込") {
                    viewModel.reload()
                }
            }
        }
        .onAppear { viewModel.reload() }
        .alert("キャッシュを削除しますか?", isPresented: $viewModel.showCacheClearConfirmation) {
            Button("削除", role: .destructive) { viewModel.clearCaches() }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("レスポンスログを削除しますか?", isPresented: $viewModel.showResponseClearConfirmation) {
            Button("削除", role: .destructive) { viewModel.clearResponses() }
            Button("キャンセル", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func cacheRow(title: String, subtitle: Date?, text: String?) -> some View {
        if let text {
            NavigationLink {
                DebugTextViewer(title: title, text: text)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle {
                        Text("更新: \(DebugToolsViewModel.dateFormatter.string(from: subtitle))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            HStack {
                Text(title)
                Spacer()
                Text("保存なし")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
    }

    private func responseRow(_ record: DebugResponseRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(record.category.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(record.category == .api ? Color.blue.opacity(0.1) : Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text(record.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(DebugToolsViewModel.dateFormatter.string(from: record.capturedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private extension HTTPCookie {
    var debugIdentifier: String { "\(name)@\(domain)" }
}

@MainActor
final class DebugToolsViewModel: ObservableObject {
    @Published var widgetSnapshot: WidgetSnapshot?
    @Published var aggregatePayload: AggregatePayload?
    @Published var responses: [DebugResponseRecord] = []
    @Published var cookies: [HTTPCookie] = []
    @Published var showCacheClearConfirmation = false
    @Published var showResponseClearConfirmation = false

    private let payloadStore = AggregatePayloadStore()
    private let widgetStore = WidgetDataStore()
    private let responseStore = DebugResponseStore.shared
    private let cookieStorage: HTTPCookieStorage? = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: AppGroup.identifier)

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var aggregatePayloadText: String? {
        aggregatePayload.flatMap { DebugPrettyFormatter.prettyJSONString($0) }
    }

    var widgetSnapshotText: String? {
        widgetSnapshot.flatMap { DebugPrettyFormatter.prettyJSONString($0) }
    }

    func reload() {
        aggregatePayload = payloadStore.load()
        widgetSnapshot = widgetStore.loadSnapshot()
        responses = responseStore.load()
        cookies = (cookieStorage?.cookies ?? []).sorted { lhs, rhs in
            lhs.name < rhs.name
        }
    }

    func clearCaches() {
        payloadStore.clear()
        widgetStore.clear()
        reload()
    }

    func clearResponses() {
        responseStore.clear()
        reload()
    }
}

struct DebugResponseDetailView: View {
    enum DisplayMode: String, CaseIterable {
        case raw = "生データ"
        case formatted = "整形後"
    }

    let record: DebugResponseRecord
    @State private var displayMode: DisplayMode = .raw

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.headline)
                Text(record.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("取得: \(DebugToolsViewModel.dateFormatter.string(from: record.capturedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(record.category.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(record.category == .api ? Color.blue.opacity(0.12) : Color.orange.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if record.formattedText != nil {
                Picker("", selection: $displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            ScrollView {
                Text(displayedText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var displayedText: String {
        switch displayMode {
        case .raw:
            return record.rawText
        case .formatted:
            return record.formattedText ?? record.rawText
        }
    }
}

struct DebugTextViewer: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }
}
