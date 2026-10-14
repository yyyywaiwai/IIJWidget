import Foundation

extension AppViewModel {
    enum LoadState {
        case idle
        case loading(previous: AggregatePayload?)
        case loaded(AggregatePayload)
        case failed(String, lastPayload: AggregatePayload?)

        var payload: AggregatePayload? {
            switch self {
            case .idle: return nil
            case .loading(let previous): return previous
            case .loaded(let payload): return payload
            case .failed(_, let lastPayload): return lastPayload
            }
        }

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }

        var errorMessage: String? {
            if case .failed(let message, _) = self { return message }
            return nil
        }
    }
}
