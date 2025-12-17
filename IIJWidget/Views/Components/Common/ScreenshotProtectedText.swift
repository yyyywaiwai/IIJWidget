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
            ScreenshotProtectedTextRepresentable(
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

private struct ScreenshotProtectedTextRepresentable: UIViewRepresentable {
    let text: String
    let font: Font
    let foregroundStyle: Color

    func makeUIView(context: Context) -> ScreenshotProtectedLabel {
        let view = ScreenshotProtectedLabel()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }

    func updateUIView(_ uiView: ScreenshotProtectedLabel, context: Context) {
        uiView.update(text: text, font: uiFont(from: font), textColor: UIColor(foregroundStyle))
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

private class ScreenshotProtectedLabel: UIView {
    private let secureTextField = UITextField()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        secureTextField.isSecureTextEntry = true
        secureTextField.isUserInteractionEnabled = false
        secureTextField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(secureTextField)

        NSLayoutConstraint.activate([
            secureTextField.topAnchor.constraint(equalTo: topAnchor),
            secureTextField.bottomAnchor.constraint(equalTo: bottomAnchor),
            secureTextField.leadingAnchor.constraint(equalTo: leadingAnchor),
            secureTextField.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        DispatchQueue.main.async { [weak self] in
            self?.addLabelToSecureContainer()
        }
    }

    private func addLabelToSecureContainer() {
        guard let secureContainer = findSecureContainer(in: secureTextField) else { return }

        label.translatesAutoresizingMaskIntoConstraints = false
        secureContainer.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: secureContainer.topAnchor),
            label.bottomAnchor.constraint(equalTo: secureContainer.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: secureContainer.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: secureContainer.trailingAnchor)
        ])
    }

    private func findSecureContainer(in view: UIView) -> UIView? {
        for subview in view.subviews {
            if type(of: subview).description().contains("CanvasView") ||
               type(of: subview).description().contains("TextLayoutCanvasView") {
                return subview
            }
            if let found = findSecureContainer(in: subview) {
                return found
            }
        }
        return nil
    }

    func update(text: String, font: UIFont, textColor: UIColor) {
        secureTextField.text = text
        secureTextField.font = font
        label.text = text
        label.font = font
        label.textColor = textColor

        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        label.intrinsicContentSize
    }
}
