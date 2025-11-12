import Foundation

extension WidgetSnapshot {
    init?(payload: AggregatePayload) {
        guard let service = payload.top.serviceInfoList.first else { return nil }
        guard let total = service.totalCapacity, total > 0 else { return nil }
        let remaining = service.remainingDataGB ?? 0
        let snapshot = WidgetServiceSnapshot(
            serviceName: service.displayPlanName,
            phoneNumber: service.phoneLabel,
            totalCapacityGB: total,
            remainingGB: remaining
        )
        self.init(fetchedAt: payload.fetchedAt, primaryService: snapshot, isRefreshing: false)
    }
}
