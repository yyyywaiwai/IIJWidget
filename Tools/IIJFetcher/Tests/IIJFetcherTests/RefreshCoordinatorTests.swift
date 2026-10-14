import XCTest
@testable import IIJFetcher

@MainActor
final class RefreshCoordinatorTests: XCTestCase {
    private enum Trigger { case automatic, manual, history }

    /// Suspension is explicit so these tests never rely on network or timer delays.
    private final class Gate {
        var isWaiting = false
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation {
                continuation = $0
                isWaiting = true
            }
        }

        func open() {
            continuation?.resume()
            continuation = nil
        }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Expected task did not reach its suspension point")
    }

    func testSameTrigger_JoinsExistingWork() async throws {
        let coordinator = RefreshCoordinator<Trigger>()
        let gate = Gate()
        var calls = 0
        let first = Task {
            await coordinator.run(trigger: .manual, canJoin: { _ in false }) {
                calls += 1
                await gate.wait()
                return .success(())
            }
        }
        await waitUntil { gate.isWaiting }
        var joined = false
        let second = Task {
            joined = true
            return await coordinator.run(trigger: .manual, canJoin: { _ in false }) {
                calls += 1
                return .success(())
            }
        }
        await waitUntil { joined }
        gate.open()
        try await first.value.get()
        try await second.value.get()
        XCTAssertEqual(calls, 1)
    }

    func testDifferentTrigger_WaitsThenRuns() async throws {
        let coordinator = RefreshCoordinator<Trigger>()
        let gate = Gate()
        var events: [String] = []
        let first = Task {
            await coordinator.run(trigger: .manual, canJoin: { _ in false }) {
                events.append("manual-start")
                await gate.wait()
                events.append("manual-end")
                return .success(())
            }
        }
        await waitUntil { gate.isWaiting }
        var queued = false
        let second = Task {
            queued = true
            return await coordinator.run(trigger: .history, canJoin: { _ in false }) {
                events.append("history")
                return .success(())
            }
        }
        await waitUntil { queued }
        XCTAssertEqual(events, ["manual-start"])
        gate.open()
        try await first.value.get()
        try await second.value.get()
        XCTAssertEqual(events, ["manual-start", "manual-end", "history"])
    }

    func testCompatibleAutomaticTrigger_JoinsManualRefresh() async throws {
        let coordinator = RefreshCoordinator<Trigger>()
        let gate = Gate()
        let first = Task {
            await coordinator.run(trigger: .manual, canJoin: { _ in false }) {
                await gate.wait()
                return .success(())
            }
        }
        await waitUntil { gate.isWaiting }
        var joined = false
        let second = Task {
            joined = true
            return await coordinator.run(trigger: .automatic, canJoin: { $0 != .history }) {
                XCTFail("Automatic refresh should share manual work")
                return .success(())
            }
        }
        await waitUntil { joined }
        gate.open()
        try await first.value.get()
        try await second.value.get()
    }

    func testCallerCancellation_DoesNotCancelOwnedRefresh() async throws {
        let coordinator = RefreshCoordinator<Trigger>()
        let gate = Gate()
        let caller = Task {
            await coordinator.run(trigger: .manual, canJoin: { _ in false }) {
                await gate.wait()
                XCTAssertFalse(Task.isCancelled)
                return .success(())
            }
        }
        await waitUntil { gate.isWaiting }
        caller.cancel()
        gate.open()
        try await caller.value.get()
    }

    func testSessionReset_InvalidatesQueuedWorkAndPreservesNewTask() async throws {
        let coordinator = RefreshCoordinator<Trigger>()
        let oldGate = Gate()
        let newGate = Gate()
        let old = Task {
            await coordinator.run(trigger: .manual, canJoin: { _ in false }) {
                await oldGate.wait()
                return .success(()) // Simulate a dependency that ignores cancellation.
            }
        }
        await waitUntil { oldGate.isWaiting }
        var queued = false
        let waiting = Task {
            queued = true
            return await coordinator.run(trigger: .history, canJoin: { _ in false }) {
                XCTFail("A request from the logged-out session must not run")
                return .success(())
            }
        }
        await waitUntil { queued }
        coordinator.cancel()
        let fresh = Task {
            await coordinator.run(trigger: .manual, canJoin: { _ in false }) {
                await newGate.wait()
                return .success(())
            }
        }
        await waitUntil { newGate.isWaiting }
        oldGate.open()
        for result in [await old.value, await waiting.value] {
            guard case .failure(let error) = result else {
                XCTFail("Session reset must return cancellation")
                continue
            }
            XCTAssertTrue(error is CancellationError)
        }
        var joiningNew = false
        let joinNew = Task {
            joiningNew = true
            return await coordinator.run(trigger: .manual, canJoin: { _ in false }) {
                XCTFail("Old completion must not clear the new in-flight task")
                return .success(())
            }
        }
        await waitUntil { joiningNew }
        newGate.open()
        try await fresh.value.get()
        try await joinNew.value.get()
    }

    func testSessionReset_BeforeOperationStartsSkipsInvalidatedWork() async throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("A deterministic pre-start cancellation requires Task.immediate")
        }

        let coordinator = RefreshCoordinator<Trigger>()
        var requested = false
        var calls = 0

        // Start run() synchronously until it awaits its owned task. Since both this
        // test and the owned task use MainActor, that task cannot begin until we
        // yield below; cancel() therefore always precedes operation() without sleeps.
        let invalidated = Task.immediate { @MainActor in
            requested = true
            return await coordinator.run(trigger: .manual, canJoin: { _ in false }) {
                calls += 1
                return .success(())
            }
        }
        XCTAssertTrue(requested)
        XCTAssertEqual(calls, 0)

        coordinator.cancel()
        let result = await invalidated.value
        guard case .failure(let error) = result else {
            return XCTFail("Invalidated work must return cancellation")
        }
        XCTAssertTrue(error is CancellationError)
        XCTAssertEqual(calls, 0, "Cancellation must skip the operation's initial side effects")

        let fresh = await coordinator.run(trigger: .manual, canJoin: { _ in false }) {
            calls += 1
            return .success(())
        }
        try fresh.get()
        XCTAssertEqual(calls, 1, "The new session must still be able to refresh")
    }

    func testFailure_ReleasesSlotForRetry() async throws {
        let coordinator = RefreshCoordinator<Trigger>()
        let failed = await coordinator.run(trigger: .manual, canJoin: { _ in false }) {
            .failure(CocoaError(.fileReadUnknown))
        }
        guard case .failure = failed else { return XCTFail("Expected failure") }
        var retried = false
        let retry = await coordinator.run(trigger: .manual, canJoin: { _ in false }) {
            retried = true
            return .success(())
        }
        try retry.get()
        XCTAssertTrue(retried)
    }
}
