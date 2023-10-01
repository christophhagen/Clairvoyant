import Foundation

/**
 A type to provide asynchronous task scheduling.

 In normal Swift environments, the ``AsyncTaskScheduler`` can be used.
 Other contexts, such as when using `SwiftNIO` event loops, may need a different type of scheduling.
 */
public protocol AsyncScheduler {

    /**
     Schedule an async operation.
     - Parameter schedule: The asynchronous function to run
     */
    func schedule(asyncJob: @escaping @Sendable () async throws -> Void)
}

/**
 The standard handler for asynchronous operations based on Swift `Task`s.
 */
struct AsyncTaskScheduler: AsyncScheduler {

    func schedule(asyncJob: @escaping @Sendable () async throws -> Void) {
        Task {
            try await asyncJob()
        }
    }
}

