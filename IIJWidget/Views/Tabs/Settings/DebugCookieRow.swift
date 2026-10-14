import SwiftUI

struct DebugCookieRow: View {
    let name: String
    let domain: String
    let value: String
    let expiresAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let expiresAt {
                Text("有効期限: \(DebugDateFormatter.string(from: expiresAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
        }
        .padding(.vertical, 4)
    }
}
