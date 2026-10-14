import SwiftUI

struct BillingHighlightCard: View {
    let bill: BillSummaryResponse
    let accentColors: AccentColorSettings
    let onSelect: ((BillSummaryResponse.BillEntry) -> Void)?

    init(
        bill: BillSummaryResponse,
        accentColors: AccentColorSettings,
        onSelect: ((BillSummaryResponse.BillEntry) -> Void)? = nil
    ) {
        self.bill = bill
        self.accentColors = accentColors
        self.onSelect = onSelect
    }

    private var accentColor: Color {
        accentColors.palette(for: .billingChart).previewSymbolColor
    }

    var body: some View {
        if let latest = bill.latestEntry {
            if let onSelect {
                Button {
                    onSelect(latest)
                } label: {
                    BillingHighlightContent(
                        entry: latest, accentColor: accentColor, isInteractive: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("タップすると請求明細を開きます")
            } else {
                BillingHighlightContent(
                    entry: latest, accentColor: accentColor, isInteractive: false)
            }
        } else {
            DashboardCard(title: "直近のご請求") {
                ChartPlaceholder(text: "請求データがありません")
            }
        }
    }

}

private struct BillingHighlightContent: View {
    let entry: BillSummaryResponse.BillEntry
    let accentColor: Color
    let isInteractive: Bool

    var body: some View {
        let isUnpaid = entry.isUnpaid == true
        DashboardCard(
            title: "最新のご請求",
            subtitle: isUnpaid ? "未払いのご請求があります" : "\(entry.formattedMonth)分のご請求はこちらです"
        ) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(entry.formattedAmount)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(isUnpaid ? Color.red : Color.primary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(entry.formattedMonth)分のご請求")
                .accessibilityValue(
                    isUnpaid ? "\(entry.formattedAmount)、未払い" : entry.formattedAmount)

                Spacer(minLength: AppSpacing.md)

                VStack(alignment: .trailing, spacing: AppSpacing.sm) {
                    if isUnpaid {
                        Label("未払い", systemImage: "exclamationmark.circle.fill")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, AppSpacing.sm + 2)
                            .padding(.vertical, AppSpacing.xs)
                            .background(Color.red.opacity(0.1), in: Capsule())
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(accentColor.gradient)
                            .padding(AppSpacing.sm + 2)
                            .background(accentColor.opacity(0.1), in: Circle())
                            .accessibilityHidden(true)
                    }

                    if isInteractive {
                        HStack(spacing: AppSpacing.xs) {
                            Text("詳細を見る")
                                .font(.system(.caption2, design: .rounded, weight: .bold))
                            Image(systemName: "chevron.right")
                                .font(.system(.caption2, weight: .heavy))
                        }
                        .foregroundStyle(accentColor)
                        .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}
