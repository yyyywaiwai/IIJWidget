import SwiftUI

struct DebugToolsView: View {
    @State private var viewModel = DebugToolsViewModel()
    @State private var showCacheClearConfirmation = false
    @State private var showResponseClearConfirmation = false

    var body: some View {
        List {
            Section("ウィジェットキャッシュ") {
                DebugCacheRow(
                    title: "AggregatePayload",
                    updatedAt: viewModel.aggregatePayloadUpdatedAt,
                    text: viewModel.aggregatePayloadText
                )

                DebugCacheRow(
                    title: "WidgetSnapshot",
                    updatedAt: viewModel.widgetSnapshotUpdatedAt,
                    text: viewModel.widgetSnapshotText
                )

                Button(role: .destructive) {
                    showCacheClearConfirmation = true
                } label: {
                    Label("キャッシュを削除", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }

            Section("レスポンス") {
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
                            DebugResponseRow(
                                title: record.title,
                                path: record.path,
                                category: record.category,
                                capturedAt: record.capturedAt
                            )
                        }
                    }
                }

                Button(role: .destructive) {
                    showResponseClearConfirmation = true
                } label: {
                    Label("レスポンスログをクリア", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .disabled(viewModel.responses.isEmpty)
            }

            Section("セッションCookie") {
                if viewModel.cookies.isEmpty {
                    Text("保存されている Cookie はありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.cookies, id: \.debugIdentifier) { cookie in
                        DebugCookieRow(
                            name: cookie.name,
                            domain: cookie.domain,
                            value: cookie.value,
                            expiresAt: cookie.expiresDate
                        )
                    }
                }
            }
        }
        .navigationTitle("デバッグツール")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("再読込") {
                    viewModel.reload()
                }
            }
        }
        .onAppear { viewModel.reload() }
        .alert("キャッシュを削除しますか?", isPresented: $showCacheClearConfirmation) {
            Button("削除", role: .destructive) { viewModel.clearCaches() }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("レスポンスログを削除しますか?", isPresented: $showResponseClearConfirmation) {
            Button("削除", role: .destructive) { viewModel.clearResponses() }
            Button("キャンセル", role: .cancel) {}
        }
    }
}
