import SwiftUI

struct InfoTipButton: View {
    let message: String
    let accessibilityLabel: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isPresented) {
            InfoTipPopover(text: message)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("ヒントを表示")
    }
}

private struct InfoTipPopover: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.leading)
            .padding(12)
            .frame(maxWidth: 260, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
