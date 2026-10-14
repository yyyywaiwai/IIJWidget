import SwiftUI

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
                Text("取得: \(DebugDateFormatter.string(from: record.capturedAt))")
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
