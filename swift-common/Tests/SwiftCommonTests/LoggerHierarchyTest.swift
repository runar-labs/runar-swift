@testable import SwiftCommon
import XCTest

final class LoggerHierarchyTest: XCTestCase {
    override func setUp() {
        super.setUp()
        // Reset global config for each test
        LoggerConfigManager.shared.globalConfig = LoggerConfig(level: .trace)
    }

    func testRootLoggerCreation() {
        let logger = RunarLogger.root(component: .ffi, context: "main")

        // Test that logger works by logging a message
        logger.info("Test root logger creation")
        // Note: We can't directly test private properties, but we can test behavior
    }

    func testChildLoggerCreation() {
        let rootLogger = RunarLogger.root(component: .ffi, context: "main")
        let childLogger = rootLogger.child(component: .network, context: "tls")

        // Test that child logger works
        childLogger.info("Test message")
    }

    func testHierarchicalLogging() {
        let rootLogger = RunarLogger.root(component: .ffi, context: "main")
        let networkLogger = rootLogger.child(component: .network, context: "tls")
        let handshakeLogger = networkLogger.child(component: .custom, context: "handshake")

        // This should output: [timestamp INFO] [ffi Network Custom main tls handshake] Test message
        handshakeLogger.info("Test message")
    }

    func testGlobalConfiguration() {
        // Set global config to INFO level
        LoggerConfigManager.shared.globalConfig = LoggerConfig(level: .info)

        let logger = RunarLogger.root(component: .service)

        // These should not output anything (level too low)
        logger.trace("This should not appear")
        logger.debug("This should not appear")

        // This should output
        logger.info("This should appear")
    }

    func testPerLoggerConfiguration() {
        // Set global config to INFO level
        LoggerConfigManager.shared.globalConfig = LoggerConfig(level: .info)

        // Create logger with specific config
        let specificConfig = LoggerConfig(level: .debug)
        let logger = RunarLogger.root(component: .service, config: specificConfig)

        // This should not output (level too low for global config)
        logger.trace("This should not appear")

        // This should output (level matches logger config)
        logger.debug("This should appear")
    }

    func testLazyEvaluation() {
        var expensiveOperationCalled = false

        func expensiveOperation() -> String {
            expensiveOperationCalled = true
            return "expensive result"
        }

        // Set global config to INFO level
        LoggerConfigManager.shared.globalConfig = LoggerConfig(level: .info)

        let logger = RunarLogger.root(component: .service)

        // This should not call expensiveOperation because TRACE is disabled
        logger.trace("Message with \(expensiveOperation())")

        XCTAssertFalse(expensiveOperationCalled, "Expensive operation should not be called when logging is disabled")

        // Reset flag
        expensiveOperationCalled = false

        // This should call expensiveOperation because INFO is enabled
        logger.info("Message with \(expensiveOperation())")

        XCTAssertTrue(expensiveOperationCalled, "Expensive operation should be called when logging is enabled")
    }

    func testLogLevelPriority() {
        let logger = RunarLogger.root(component: .service)

        // Test all levels
        logger.trace("Trace message")
        logger.debug("Debug message")
        logger.info("Info message")
        logger.warning("Warning message")
        logger.error("Error message")
    }

    func testComponentDisplayNames() {
        XCTAssertEqual(Component.ffi.displayName, "ffi")
        XCTAssertEqual(Component.network.displayName, "Network")
        XCTAssertEqual(Component.service.displayName, "Service")
        XCTAssertEqual(Component.registry.displayName, "Registry")
        XCTAssertEqual(Component.transporter.displayName, "Transporter")
        XCTAssertEqual(Component.serializer.displayName, "Serializer")
        XCTAssertEqual(Component.node.displayName, "Node")
        XCTAssertEqual(Component.custom.displayName, "Custom")
    }

    func testLogLevelPriorityValues() {
        XCTAssertEqual(LogLevel.trace.priority, 0)
        XCTAssertEqual(LogLevel.debug.priority, 1)
        XCTAssertEqual(LogLevel.info.priority, 2)
        XCTAssertEqual(LogLevel.warning.priority, 3)
        XCTAssertEqual(LogLevel.error.priority, 4)
    }
}
