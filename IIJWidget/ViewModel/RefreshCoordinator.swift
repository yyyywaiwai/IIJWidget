import Foundation

/// Serializes refresh work independently of the lifetime of a SwiftUI task.
/// A session reset invalidates both active work and callers waiting to start work.
@MainActor
final class RefreshCoordinator<Trigger: Equatable> {
    private struct InFlight {
        let id: UUID
        let trigger: Trigger
        let task: Task<Result<Void, Error>, Never>
    }

    private var inFlight: InFlight?
    private var generation = UUID()

    func run(
        trigger: Trigger,
        canJoin: (Trigger) -> Bool,
        operation: @escaping @MainActor () async -> Result<Void, Error>
    ) async -> Result<Void, Error> {
        let requestedGeneration = generation
        while let current = inFlight {
            let result = await current.task.value
            guard generation == requestedGeneration else {
                return .failure(CancellationError())
            }
            if current.trigger == trigger || canJoin(current.trigger) {
                return result
            }
        }
        guard !Task.isCancelled, generation == requestedGeneration else {
            return .failure(CancellationError())
        }

        let id = UUID()
        let task = Task<Result<Void, Error>, Never> { @MainActor [weak self] in
            defer {
                // A cancelled task may finish after a new session's task started.
                if self?.inFlight?.id == id {
                    self?.inFlight = nil
                }
            }
            guard !Task.isCancelled, self?.generation == requestedGeneration else {
                return .failure(CancellationError())
            }
            return await operation()
        }
        inFlight = InFlight(id: id, trigger: trigger, task: task)
        let result = await task.value
        guard generation == requestedGeneration else {
            return .failure(CancellationError())
        }
        return result
    }

    func cancel() {
        generation = UUID()
        inFlight?.task.cancel()
        inFlight = nil
    }
}
