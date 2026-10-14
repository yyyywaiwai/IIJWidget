import SwiftUI

struct SettingsProjectSection: View {
    private static let repositoryURL = URL(string: "https://github.com/yyyywaiwai/IIJWidget")

    var body: some View {
        Section("プロジェクト") {
            if let repositoryURL = Self.repositoryURL {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Link(destination: repositoryURL) {
                        Label("GitHub リポジトリを開く", systemImage: "arrow.up.right.square")
                    }
                    InfoTipButton(
                        message: "このアプリはオープンソースです。MITライセンスの規約に従って自由にコードを利用できます",
                        accessibilityLabel: "GitHub リポジトリのヒント"
                    )
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
