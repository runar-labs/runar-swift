import Foundation
import XCTest

/// Shared test utilities for RunarTransporter tests
/// This file contains common test helpers to avoid duplication

/// Base test class with timeout support
@available(macOS 12.0, iOS 15.0, *)
class TimeoutTestCase: XCTestCase {
    /// Default timeout for tests in this class
    var testTimeout: TimeInterval { 30.0 }

    /// Run a test operation with timeout
    func runWithTimeoutClass<T>(_ timeout: TimeInterval? = nil, operation: @escaping () async throws -> T) async throws -> T {
        let actualTimeout = timeout ?? testTimeout
        return try await runWithTimeout(actualTimeout, operation: operation)
    }

    /// Run a test operation with timeout (void version)
    func runWithTimeoutVoidClass(_ timeout: TimeInterval? = nil, operation: @escaping () async throws -> Void) async throws {
        let actualTimeout = timeout ?? testTimeout
        try await runWithTimeoutVoid(actualTimeout, operation: operation)
    }
}

/// Helper function to run tests with timeout
/// Ensures tests don't hang indefinitely
func runWithTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw TestTimeoutError(timeout: timeout)
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

/// Helper function to run tests with timeout (void version)
/// Ensures tests don't hang indefinitely
func runWithTimeoutVoid(_ timeout: TimeInterval, operation: @escaping () async throws -> Void) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw TestTimeoutError(timeout: timeout)
        }

        _ = try await group.next()!
        group.cancelAll()
    }
}

/// Error thrown when a test times out
struct TestTimeoutError: Error, LocalizedError {
    let timeout: TimeInterval

    var errorDescription: String? {
        "Test timed out after \(timeout) seconds"
    }
}
