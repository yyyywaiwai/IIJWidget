import SwiftUI

/// アプリ内で共有するレイアウト定数。
/// 画面ごとに数値を直書きすると余白やコーナー半径がずれるため、ここに集約する。
enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

enum AppRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
}

/// カード表面の縁取りスタイル。
enum CardStroke {
    /// 白系グラデーション。汎用のガラス面に使う。
    case neutral
    /// アクセントカラーで縁取る。カード内容と色を揃えたい場合に使う。
    case tinted([Color])
}

/// カード表面の影の強さ。
enum CardElevation {
    case flat
    case raised
}

extension View {
    /// 各画面にコピーされていたガラス調カード表面を一箇所に集約したモディファイア。
    /// 余白は呼び出し側の責務とし、ここでは塗り・縁取り・影のみを適用する。
    func cardSurface(
        cornerRadius: CGFloat = AppRadius.xl,
        material: Material = .thinMaterial,
        stroke: CardStroke = .neutral,
        elevation: CardElevation = .raised
    ) -> some View {
        modifier(
            CardSurfaceModifier(
                cornerRadius: cornerRadius,
                material: material,
                stroke: stroke,
                elevation: elevation
            )
        )
    }
}

private struct CardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let material: Material
    let stroke: CardStroke
    let elevation: CardElevation
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                shape
                    .fill(material)
                    .overlay {
                        shape.stroke(strokeGradient, lineWidth: 1)
                    }
                    .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowOffsetY)
            }
    }

    private var strokeGradient: LinearGradient {
        switch stroke {
        case .neutral:
            return LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.12 : 0.5),
                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .tinted(let colors):
            return LinearGradient(
                colors: [
                    colors.first?.opacity(0.3) ?? .clear,
                    colors.last?.opacity(0.1) ?? .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var shadowColor: Color {
        switch elevation {
        case .flat:
            return .clear
        case .raised:
            return Color.black.opacity(colorScheme == .dark ? 0.25 : 0.05)
        }
    }

    private var shadowRadius: CGFloat {
        switch elevation {
        case .flat: return 0
        case .raised: return 12
        }
    }

    private var shadowOffsetY: CGFloat {
        switch elevation {
        case .flat: return 0
        case .raised: return 6
        }
    }
}
/// 利用量タブとホームのグラフ切替に個別実装されていたカプセル型セグメントコントロールを統合したもの。
/// 選択中のピルは `matchedGeometryEffect` で滑らかに移動する。
struct SegmentedSelector<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let systemImage: (Item) -> String
    let gradientColors: (Item) -> [Color]

    @Namespace private var indicatorNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                segment(for: item)
            }
        }
        .padding(AppSpacing.xs)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.06))
        )
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func segment(for item: Item) -> some View {
        let isSelected = selection == item
        let colors = gradientColors(item)

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selection = item
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: systemImage(item))
                    .font(.system(size: 14, weight: .semibold))
                Text(title(item))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(
                            color: colors.first?.opacity(0.4) ?? .clear,
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                        .matchedGeometryEffect(id: "selectedSegment", in: indicatorNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(item))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// セクション見出し。アイコンをアクセントグラデーションで塗る共通スタイル。
struct SectionHeader: View {
    let title: String
    let systemImage: String
    let gradientColors: [Color]

    var body: some View {
        HStack(spacing: AppSpacing.sm + 2) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
