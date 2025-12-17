import SwiftUI
import UIKit

struct ScreenshotProtectedText: View {
    let text: String
    let font: Font
    let foregroundStyle: Color
    let isProtected: Bool

    init(
        _ text: String,
        font: Font = .body,
        foregroundStyle: Color = .primary,
        isProtected: Bool = true
    ) {
        self.text = text
        self.font = font
        self.foregroundStyle = foregroundStyle
        self.isProtected = isProtected
    }

    var body: some View {
        if isProtected {
            SecureTextFieldRepresentable(
                text: text,
                font: font,
                foregroundStyle: foregroundStyle
            )
            .fixedSize()
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(foregroundStyle)
        }
    }
}

private struct SecureTextFieldRepresentable: UIViewRepresentable {
    let text: String
    let font: Font
    let foregroundStyle: Color

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.isSecureTextEntry = true
        textField.isUserInteractionEnabled = false
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.setContentHuggingPriority(.required, for: .horizontal)
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .horizontal)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
        uiView.font = uiFont(from: font)
        uiView.textColor = UIColor(foregroundStyle)
    }

    private func uiFont(from font: Font) -> UIFont {
        switch font {
        case .largeTitle:
            return UIFont.preferredFont(forTextStyle: .largeTitle)
        case .title:
            return UIFont.preferredFont(forTextStyle: .title1)
        case .title2:
            return UIFont.preferredFont(forTextStyle: .title2)
        case .title3:
            return UIFont.preferredFont(forTextStyle: .title3)
        case .headline:
            return UIFont.preferredFont(forTextStyle: .headline)
        case .subheadline:
            return UIFont.preferredFont(forTextStyle: .subheadline)
        case .body:
            return UIFont.preferredFont(forTextStyle: .body)
        case .callout:
            return UIFont.preferredFont(forTextStyle: .callout)
        case .footnote:
            return UIFont.preferredFont(forTextStyle: .footnote)
        case .caption:
            return UIFont.preferredFont(forTextStyle: .caption1)
        case .caption2:
            return UIFont.preferredFont(forTextStyle: .caption2)
        default:
            return UIFont.preferredFont(forTextStyle: .subheadline)
        }
    }
}
