import SwiftUI

struct BillSummaryList: View {
    let bill: BillSummaryResponse
    let accentColors: AccentColorSettings
    let onSelect: ((BillSummaryResponse.BillEntry) -> Void)?
    private var entries: [BillSummaryResponse.BillEntry] {
        Array(bill.billList.prefix(12))
    }

    init(
        bill: BillSummaryResponse,
        accentColors: AccentColorSettings,
        onSelect: ((BillSummaryResponse.BillEntry) -> Void)? = nil
    ) {
        self.bill = bill
        self.accentColors = accentColors
        self.onSelect = onSelect
    }

    var body: some View {
        let entries = self.entries
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("直近の請求金額")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            ForEach(entries) { entry in
                BillSummaryRow(
                    entry: entry,
                    accentColor: accentColors.palette(for: .billingChart).previewSymbolColor,
                    onSelect: onSelect,
                    showsDivider: entry.id != entries.last?.id
                )
            }
        }
    }

}

private struct BillSummaryRow: View {
    let entry: BillSummaryResponse.BillEntry
    let accentColor: Color
    let onSelect: ((BillSummaryResponse.BillEntry) -> Void)?
    let showsDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            selectionContent
            if showsDivider {
                Divider()
            }
        }
    }

    @ViewBuilder
    private var selectionContent: some View {
        if let onSelect {
            Button {
                onSelect(entry)
            } label: {
                BillSummaryRowContent(entry: entry, accentColor: accentColor, isInteractive: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("タップすると明細を開きます")
        } else {
            BillSummaryRowContent(entry: entry, accentColor: accentColor, isInteractive: false)
        }
    }

}

private struct BillSummaryRowContent: View {
    let entry: BillSummaryResponse.BillEntry
    let accentColor: Color
    let isInteractive: Bool

    var body: some View {
        let isUnpaid = entry.isUnpaid == true
        HStack(spacing: AppSpacing.md) {
            let statusColor: Color =
                isUnpaid ? .red : accentColor

            Image(systemName: isUnpaid ? "exclamationmark.circle.fill" : "doc.text.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(statusColor)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.formattedMonth)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)

                if isUnpaid {
                    Text("未払い")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.red)
                } else {
                    Text("お支払い完了")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            Text(entry.formattedAmount)
                .font(.system(.body, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isUnpaid ? Color.red : Color.primary)

            if isInteractive {
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, AppSpacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.formattedMonth)
        .accessibilityValue(
            isUnpaid ? "\(entry.formattedAmount)、未払い" : "\(entry.formattedAmount)")
    }
}
