import XCTest

/// Helper functions for async testing
extension XCTestCase {
    /// Assert that an async throwing expression does not throw
    @MainActor
    func XCTAssertNoThrowAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
        } catch {
            XCTFail("Expected no error but got: \(error). \(message())", file: file, line: line)
        }
    }
    
    /// Assert that an async throwing expression throws an error
    @MainActor
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error but none was thrown. \(message())", file: file, line: line)
        } catch {
            // Expected to throw
        }
    }
}
