import SwiftUI

struct ServiceStatusList: View {
    let status: ServiceStatusResponse

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            ForEach(status.serviceInfoList) { item in
                ServiceStatusCard(item: item)
            }
        }
    }
}

private struct ServiceStatusCard: View {
    let item: ServiceStatusResponse.ServiceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs + 2) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(item.serviceCodePrefix ?? "-")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("サービスコード")

            HStack(spacing: AppSpacing.xs + 2) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(item.planCode ?? "-")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("プランコード")

            if let simList = item.simInfoList {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(simList) { sim in
                        SIMStatusBadge(sim: sim)
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(
            cornerRadius: AppRadius.sm,
            material: .ultraThinMaterial,
            elevation: .flat
        )
    }
}

private struct SIMStatusBadge: View {
    let sim: ServiceStatusResponse.ServiceStatus.SimInfo

    var body: some View {
        let isActive = sim.status == "利用中"
        HStack(spacing: AppSpacing.xs) {
            Image(
                systemName: isActive ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .font(.system(size: 12))
            Text([sim.simType, sim.status].compactMap { $0 }.joined(separator: "・"))
                .font(.system(.caption, design: .rounded, weight: .medium))
        }
        .foregroundStyle(isActive ? Color.green : Color.orange)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(
            Capsule()
                .fill((isActive ? Color.green : Color.orange).opacity(0.12))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sim.simType ?? "SIM")
        .accessibilityValue(sim.status ?? "状態未取得")
    }
}
