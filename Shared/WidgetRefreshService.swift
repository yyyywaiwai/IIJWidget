import Foundation

struct WidgetRefreshService {
    enum LoginSource { case gapiToken, gapiKeychain, gapiManual, mock }
    enum FetchScope { case full, topOnly }

    struct RefreshOutcome {
        let payload: AggregatePayload
        let loginSource: LoginSource
    }

    private let credentialStore = CredentialStore()
    private let gapiClient = MyIIJmioAPIClient()
    private let dailyClient = ThirtyDayUsageClient()
    private let widgetDataStore = WidgetDataStore()
    private let payloadStore = AggregatePayloadStore()
    private let debugStore = DebugResponseStore.shared

    func refreshForWidget(forceGAPIUpdate: Bool = false) async throws -> RefreshOutcome {
        // 月間通知の判定には今回取得した月次値が必要。30日表はここでは取得しない。
        let reuseHistory = PayloadRefreshPolicy.canReuseHistory(
            cached: payloadStore.load(),
            forceUpdate: forceGAPIUpdate,
            needsFreshMonthlyUsage: UsageAlertStore().load().needsFreshMonthlyUsage
        )
        return try await refresh(fetchScope: reuseHistory ? .topOnly : .full, forceGAPIUpdate: forceGAPIUpdate)
    }

    func refresh(
        manualCredentials: Credentials? = nil,
        persistManualCredentials: Bool = true,
        allowSessionReuse: Bool = true,
        allowKeychainFallback: Bool = true,
        fetchScope: FetchScope = .full,
        forceGAPIUpdate: Bool = false
    ) async throws -> RefreshOutcome {
        debugStore.beginCaptureSession()
        defer { debugStore.finalizeCaptureSession() }
        if let mock = mockOutcome(manualCredentials: manualCredentials,
                                  persistManualCredentials: persistManualCredentials,
                                  allowKeychainFallback: allowKeychainFallback) { return mock }
        if !allowSessionReuse { clearSessionArtifacts() }
        let stored = allowKeychainFallback ? try credentialStore.load() : nil
        let credentials = manualCredentials ?? stored
        let cached = payloadStore.load()
        var source: LoginSource = .gapiToken
        let fetched: FetchedPayload

        func fetch(_ credentials: Credentials?) async throws -> FetchedPayload {
            try await fetchPayload(
                credentials: credentials,
                cached: cached,
                scope: fetchScope,
                forceUpdate: forceGAPIUpdate
            )
        }

        if allowSessionReuse {
            do {
                fetched = try await fetch(nil)
            } catch {
                guard gapiClient.isAuthenticationError(error) else { throw error }
                gapiClient.clearPersistedSession()
                guard let credentials else { throw WidgetRefreshError.missingCredentials }
                fetched = try await fetch(credentials)
                source = manualCredentials != nil ? .gapiManual : .gapiKeychain
            }
        } else {
            guard let credentials else { throw WidgetRefreshError.missingCredentials }
            fetched = try await fetch(credentials)
            source = manualCredentials != nil ? .gapiManual : .gapiKeychain
        }
        // 通常更新はGAPIのみ。取得済みの30日表は現存する回線分だけ保持する。
        let result = PayloadRefreshPolicy.retainingHistory(in: fetched.payload, from: payloadStore.load())
        try Task.checkCancellation()
        if allowKeychainFallback, try credentialStore.load() != stored { throw CancellationError() }
        if persistManualCredentials, let manualCredentials { try credentialStore.save(manualCredentials) }
        let outcome = finalize(payload: result, source: source)
        if let accountID = try? MyIIJmioTokenStore().load()?.mioId {
            await UsageAlertNotifier.notify(payload: result, freshDailyUsage: fetched.freshDailyUsage, accountID: accountID)
        }
        return outcome
    }

    /// 利用量タブを開いた時だけ取得する。GAPIの更新日時や認証状態は変更しない。
    func refreshUsageHistory() async throws -> AggregatePayload {
        guard let cached = payloadStore.load() else { throw MyIIJmioAPIError.invalidResponse }
        let credentials = try credentialStore.load()
        if let credentials, MockPayloadProvider.isMockCredentials(credentials) { return cached }
        debugStore.beginCaptureSession()
        defer { debugStore.finalizeCaptureSession() }

        let history: [DailyUsageService]
        do {
            history = try await dailyClient.fetchThirtyDays()
        } catch {
            guard dailyClient.isAuthenticationError(error) else { throw error }
            guard let credentials else { throw WidgetRefreshError.missingCredentials }
            history = try await dailyClient.fetchThirtyDays(credentials: credentials)
        }
        let normalized = try DailyUsageMerger.match(history: history, lines: cached.top.serviceInfoList)
        try Task.checkCancellation()
        // 取得中のWidget更新を巻き戻さず、ログアウト・アカウント/回線変更後には保存しない。
        guard var latest = payloadStore.load(),
              PayloadRefreshPolicy.hasSameLines(latest.top, cached.top),
              try credentialStore.load() == credentials else { throw ThirtyDayUsageError.invalidSession }
        latest.thirtyDayUsage = normalized
        payloadStore.save(payload: latest)
        return latest
    }

    /// Carries freshly fetched values separately from merged history for notification evaluation.
    private struct FetchedPayload {
        let payload: AggregatePayload
        let freshDailyUsage: [DailyUsageService]
    }

    private func fetchPayload(
        credentials: Credentials?,
        cached: AggregatePayload?,
        scope: FetchScope,
        forceUpdate: Bool
    ) async throws -> FetchedPayload {
        if scope == .topOnly, let cached {
            let latest: (top: TrafficSummary, dailyUsage: [DailyUsageService])
            if let credentials {
                latest = try await gapiClient.fetchTop(credentials: credentials, forceUpdate: forceUpdate)
            } else {
                latest = try await gapiClient.fetchTopUsingExistingSession(forceUpdate: forceUpdate)
            }
            if let merged = PayloadRefreshPolicy.mergingTop(latest.top, dailyUsage: latest.dailyUsage, into: cached) {
                return FetchedPayload(payload: merged, freshDailyUsage: latest.dailyUsage)
            }
        }

        let payload: AggregatePayload
        if let credentials {
            payload = try await gapiClient.fetchAll(credentials: credentials, forceUpdate: forceUpdate)
        } else {
            payload = try await gapiClient.fetchAllUsingExistingSession(forceUpdate: forceUpdate)
        }
        return FetchedPayload(payload: payload, freshDailyUsage: payload.dailyUsage)
    }

    private func finalize(payload: AggregatePayload, source: LoginSource) -> RefreshOutcome {
        payloadStore.save(payload: payload)
        let previousSnapshot = widgetDataStore.loadSnapshot()
        if var snapshot = WidgetSnapshot(payload: payload, fallback: previousSnapshot) {
            if previousSnapshot?.isRefreshing == true {
                snapshot = snapshot.updatingRefreshingState(true)
            }
            snapshot = snapshot.updatingSuccessUntil(Date().addingTimeInterval(3))
            widgetDataStore.save(snapshot: snapshot)
        }
        if let formattedPayload = DebugPrettyFormatter.prettyJSONString(payload) {
            debugStore.appendResponse(
                title: "AggregatePayload",
                path: "payload",
                category: .api,
                rawText: formattedPayload,
                formattedText: formattedPayload
            )
        }
        return RefreshOutcome(payload: payload, loginSource: source)
    }

    private func mockOutcome(
        manualCredentials: Credentials?,
        persistManualCredentials: Bool,
        allowKeychainFallback: Bool
    ) -> RefreshOutcome? {
        if let manualCredentials, MockPayloadProvider.isMockCredentials(manualCredentials) {
            if persistManualCredentials {
                try? credentialStore.save(manualCredentials)
            }
            return finalize(payload: MockPayloadProvider.aggregatePayload(), source: .mock)
        }

        if allowKeychainFallback,
           let stored = try? credentialStore.load(),
           MockPayloadProvider.isMockCredentials(stored) {
            return finalize(payload: MockPayloadProvider.aggregatePayload(), source: .mock)
        }

        return nil
    }


    func fetchBillDetail(entry: BillSummaryResponse.BillEntry, manualCredentials: Credentials? = nil) async throws -> BillDetailResponse {
        if let manualCredentials, MockPayloadProvider.isMockCredentials(manualCredentials) {
            guard let detail = MockPayloadProvider.billDetail(for: entry) else { throw MyIIJmioAPIError.invalidResponse }
            return detail
        }
        if let stored = try credentialStore.load(), MockPayloadProvider.isMockCredentials(stored) {
            guard let detail = MockPayloadProvider.billDetail(for: entry) else { throw MyIIJmioAPIError.invalidResponse }
            return detail
        }
        if let detail = payloadStore.load()?.billDetails[entry.id] { return detail }
        do {
            return try await gapiClient.fetchBillDetailUsingExistingSession(entry: entry)
        } catch {
            guard gapiClient.isAuthenticationError(error) else { throw error }
            gapiClient.clearPersistedSession()
        }
        guard let credentials = try manualCredentials ?? credentialStore.load() else {
            throw WidgetRefreshError.missingCredentials
        }
        return try await gapiClient.fetchBillDetail(entry: entry, credentials: credentials)
    }

    func clearSessionArtifacts() {
        gapiClient.clearPersistedSession()
        dailyClient.clearPersistedSession()
        payloadStore.clear()
        widgetDataStore.clear()
    }
}
