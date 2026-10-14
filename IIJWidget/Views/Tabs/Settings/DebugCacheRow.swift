import SwiftUI

struct DebugCacheRow: View {
    let title: String
    let updatedAt: Date?
    let text: String?

    var body: some View {
        if let text {
            NavigationLink {
                DebugTextViewer(title: title, text: text)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let updatedAt {
                        Text("更新: \(DebugDateFormatter.string(from: updatedAt))")
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
}
