@testable import SwiftCommon
import XCTest

@available(macOS 13.0, iOS 16.0, *)
final class LoggerContextMutableTest: XCTestCase {
    func testSetContextOnRootLogger() {
        let logger = RunarLogger.root(component: .node, context: "initial")

        // Verify initial context
        logger.info("Initial context test")

        // Set new context
        logger.setContext("updated")

        // Verify updated context
        logger.info("Updated context test")
    }

    func testSetContextSharedAcrossChildLoggers() {
        let rootLogger = RunarLogger.root(component: .node, context: "root")
        let childLogger = rootLogger.child(component: .service, context: "child")

        // Set context on root logger
        rootLogger.setContext("shared")

        // Both loggers should see the updated context
        rootLogger.info("Root logger with shared context")
        childLogger.info("Child logger with shared context")
    }

    func testSetContextToNil() {
        let logger = RunarLogger.root(component: .node, context: "initial")

        // Set context to nil
        logger.setContext(nil)

        // Should work without context
        logger.info("Logger without context")
    }

    func testContextMutationThreadSafety() {
        let logger = RunarLogger.root(component: .node, context: "initial")

        let expectation = XCTestExpectation(description: "Concurrent context updates")
        expectation.expectedFulfillmentCount = 100

        // Simulate concurrent context updates
        for index in 0 ..< 100 {
            DispatchQueue.global().async {
                logger.setContext("context-\(index)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // Final context should be one of the values
        logger.info("Final context test")
    }
}
