import Combine
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppViewModel: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case loaded(AggregatePayload)
        case failed(String)
    }

    @Published var mioId: String = ""
    @Published var password: String = ""
    @Published private(set) var state: LoadState = .idle

    private let credentialStore = CredentialStore()
    private let widgetRefreshService = WidgetRefreshService()

    init() {
        if let saved = try? credentialStore.load() {
            mioId = saved.mioId
            password = saved.password
        }
    }

    var canSubmit: Bool {
        !mioId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }

    func fetchLatest() async {
        guard canSubmit else {
            state = .failed("mioID とパスワードを入力してください")
            return
        }

        state = .loading
        do {
            let credentials = Credentials(mioId: mioId, password: password)
            try credentialStore.save(credentials)
            let payload = try await widgetRefreshService.refresh(using: credentials)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.remainingData)
            state = .loaded(payload)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
