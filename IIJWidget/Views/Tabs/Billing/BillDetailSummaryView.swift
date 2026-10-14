import SwiftUI

struct BillDetailSummaryView: View {
    let detail: BillDetailResponse

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(detail.monthText)
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text(detail.totalAmountText)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardSurface(cornerRadius: AppRadius.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(detail.monthText)の合計")
        .accessibilityValue(detail.totalAmountText)
    }
}

struct BillTaxBreakdownView: View {
    let breakdowns: [BillDetailResponse.TaxBreakdown]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("税区分")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            ForEach(breakdowns) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.label)
                        if let taxLabel = entry.taxLabel, !taxLabel.isEmpty {
                            Text(taxLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: AppSpacing.sm)
                    VStack(alignment: .trailing) {
                        Text(entry.amountText)
                            .bold()
                            .monospacedDigit()
                        if let taxAmount = entry.taxAmountText {
                            Text(taxAmount)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                if entry.id != breakdowns.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: AppRadius.md, material: .ultraThinMaterial, elevation: .flat)
    }
}

struct BillDetailSectionView: View {
    let section: BillDetailResponse.Section

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(section.title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            ForEach(section.items) { item in
                BillDetailItemRow(item: item)
                if item.id != section.items.last?.id {
                    Divider()
                }
            }
            if let subtotal = section.subtotalText {
                HStack {
                    Text("小計")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: AppSpacing.sm)
                    Text(subtotal)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: AppRadius.md, material: .regularMaterial)
    }
}

struct BillDetailItemRow: View {
    let item: BillDetailResponse.Item

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                if let detail = item.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: AppSpacing.sm)
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                if let quantity = item.quantityText {
                    Text("数量 \(quantity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let unit = item.unitPriceText {
                    Text("単価 \(unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let amount = item.amountText {
                    Text(amount)
                        .font(.body.bold())
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
