import SwiftUI

struct RefreshLogView: View {
    @State private var entries: [RefreshLogEntry] = []
    @State private var showClearConfirmation = false
    private let logStore = RefreshLogStore()

    var body: some View {
        List {
            if entries.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("記録がありません")
                            .font(.headline)
                        Text("ウィジェットの自動・手動更新が実行されるとここに履歴が表示されます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
            } else {
                Section(header: Text("最新50件")) {
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("リフレッシュログ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !entries.isEmpty {
                    Button("クリア") {
                        showClearConfirmation = true
                    }
                }
            }
        }
        .alert("ログをすべて削除しますか?", isPresented: $showClearConfirmation) {
            Button("削除", role: .destructive) {
                logStore.clear()
                reload()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .onAppear(perform: reload)
        .refreshable { reload() }
    }

    private func entryRow(_ entry: RefreshLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                statusBadge(for: entry.result)
                Text(entry.trigger.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(RefreshLogView.dateFormatter.string(from: entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = entry.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusBadge(for result: RefreshLogEntry.Result) -> some View {
        let iconName = result == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        let color: Color = result == .success ? .green : .red
        return Label(result.displayName, systemImage: iconName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
    }

    private func reload() {
        entries = logStore.load()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}

#Preview {
    NavigationView {
        RefreshLogView()
    }
}
