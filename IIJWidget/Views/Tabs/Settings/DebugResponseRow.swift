import SwiftUI

struct DebugResponseRow: View {
    let title: String
    let path: String
    let category: DebugResponseRecord.Category
    let capturedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(category.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(category == .api ? Color.blue.opacity(0.1) : Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(DebugDateFormatter.string(from: capturedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
