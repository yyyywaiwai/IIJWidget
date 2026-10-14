import SwiftUI

struct SettingsDebugSection: View {
    var body: some View {
        Section {
            NavigationLink {
                DebugToolsView()
            } label: {
                DebugHintRow(
                    title: "キャッシュ・レスポンス確認",
                    systemImage: "ladybug",
                    hintText: "直近のAPIレスポンスをキャッシュから確認できます。",
                    hintAccessibilityLabel: "キャッシュ・レスポンス確認のヒント"
                )
            }

            NavigationLink {
                RefreshLogView()
            } label: {
                DebugHintRow(
                    title: "リフレッシュログを確認",
                    systemImage: "doc.text.magnifyingglass",
                    hintText: "更新の実行履歴と結果を確認できます。",
                    hintAccessibilityLabel: "リフレッシュログのヒント"
                )
            }
        } header: {
            Text("デバッグ")
        } footer: {
            Text("作者から調査依頼があった時のみ使用してください。")
                .font(.footnote)
        }
    }
}

private struct DebugHintRow: View {
    let title: String
    let systemImage: String
    let hintText: String
    let hintAccessibilityLabel: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Color.accentColor)
            InfoTipButton(
                message: hintText,
                accessibilityLabel: hintAccessibilityLabel
            )
            Spacer(minLength: 0)
        }
    }
}
