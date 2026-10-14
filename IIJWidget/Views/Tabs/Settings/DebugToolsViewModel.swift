import Foundation
import Observation

@Observable
@MainActor
final class DebugToolsViewModel {
    private(set) var aggregatePayloadUpdatedAt: Date?
    private(set) var aggregatePayloadText: String?
    private(set) var widgetSnapshotUpdatedAt: Date?
    private(set) var widgetSnapshotText: String?
    private(set) var responses: [DebugResponseRecord] = []
    private(set) var cookies: [HTTPCookie] = []

    private let payloadStore = AggregatePayloadStore()
    private let widgetStore = WidgetDataStore()
    private let responseStore = DebugResponseStore.shared
    private let cookieStorage = HTTPCookieStorage.sharedCookieStorage(
        forGroupContainerIdentifier: AppGroup.identifier
    )

    func reload() {
        let payload = payloadStore.load()
        let snapshot = widgetStore.loadSnapshot()
        aggregatePayloadUpdatedAt = payload?.fetchedAt
        widgetSnapshotUpdatedAt = snapshot?.fetchedAt

        // Serialize once per reload, rather than during SwiftUI body evaluation.
        aggregatePayloadText = payload.flatMap { DebugPrettyFormatter.prettyJSONString($0) }
        widgetSnapshotText = snapshot.flatMap { DebugPrettyFormatter.prettyJSONString($0) }
        responses = responseStore.load()
        cookies = (cookieStorage.cookies ?? []).sorted { lhs, rhs in
            (lhs.name, lhs.domain, lhs.path) < (rhs.name, rhs.domain, rhs.path)
        }
    }

    func clearCaches() {
        payloadStore.clear()
        widgetStore.clear()
        reload()
    }

    func clearResponses() {
        responseStore.clear()
        reload()
    }
}

extension HTTPCookie {
    /// A cookie's identity includes its path; names can repeat within one domain.
    var debugIdentifier: String { "\(name)@\(domain)\(path)" }
}
