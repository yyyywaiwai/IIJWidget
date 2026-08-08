import SwiftUI

/// 空状態の共通表示。iOS 17 標準の `ContentUnavailableView` に寄せて
/// 見出し・説明・任意のアクションを構造化する。
struct EmptyStateView<Actions: View>: View {
    let title: String
    let message: String?
    let systemImage: String
    @ViewBuilder private let actions: () -> Actions

    init(
        title: String,
        message: String? = nil,
        systemImage: String = "rectangle.on.rectangle.slash",
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .font(.system(.headline, design: .rounded, weight: .bold))
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            actions()
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(
        title: String,
        message: String? = nil,
        systemImage: String = "rectangle.on.rectangle.slash"
    ) {
        self.init(title: title, message: message, systemImage: systemImage) {
            EmptyView()
        }
    }
}

struct PlaceholderRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.sm)
    }
}
