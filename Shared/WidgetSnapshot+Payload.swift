import Foundation

extension WidgetSnapshot {
    init?(payload: AggregatePayload, fallback: WidgetSnapshot? = nil) {
        guard let service = payload.top.serviceInfoList.first else { return nil }

        let remaining = service.remainingDataGB
            ?? fallback?.primaryService?.remainingGB
            ?? 0

        let payloadTotal = service.totalCapacity ?? 0
        let fallbackTotal = fallback?.primaryService?.totalCapacityGB ?? 0
        var total = payloadTotal > 0 ? payloadTotal : (fallbackTotal > 0 ? fallbackTotal : 0)
        if total <= 0 {
            // 0GB 返却や容量欠落時でも更新を通すため、残量か最小値で安全に補完する
            total = max(remaining, 0.01)
        }

        let snapshot = WidgetServiceSnapshot(
            serviceName: service.displayPlanName,
            phoneNumber: service.phoneLabel,
            totalCapacityGB: total,
            remainingGB: remaining
        )
        let isRefreshing = fallback?.isRefreshing ?? false
        self.init(fetchedAt: payload.fetchedAt, primaryService: snapshot, isRefreshing: isRefreshing)
    }
}
