import Foundation
import SwiftCommon
import XCTest

final class SerializerTestVectorsTests: XCTestCase {
    func testCompactIdGeneration() {
        // Test DNS-safe compact ID generation
        let id = CompactIdGenerator.generate()
        XCTAssertTrue(CompactIdGenerator.isValidCompactId(id))
        XCTAssertEqual(id.count, 20)

        // Test custom length
        let customId = CompactIdGenerator.generate(length: 10)
        XCTAssertEqual(customId.count, 10)
        XCTAssertTrue(CompactIdGenerator.isValidCompactId(customId))

        // Test prefixed generation
        let prefixedId = CompactIdGenerator.generateWithPrefix("node")
        XCTAssertTrue(prefixedId.hasPrefix("node"))
        XCTAssertTrue(CompactIdGenerator.isValidCompactId(String(prefixedId.dropFirst(4))))
    }

    func testComponentBasedLogging() {
        // Test component-based logging structure
        let logger = RunarLogger(component: .node)

        // This is mainly a compile-time test to ensure the logging system works
        // In a real test, we would capture log output, but for now we just verify
        // that the logging methods exist and can be called
        logger.debug("Test debug message")
        logger.info("Test info message")
        logger.warning("Test warning message")
        logger.error("Test error message")
        logger.critical("Test critical message")

        // Test child logger creation
        let childLogger = logger.withComponent(.registry)
        childLogger.info("Test child logger")
    }

    func testErrorHandling() {
        // Test error creation and context
        let context = ErrorContext(
            nodeId: "test-node",
            servicePath: "test/service",
            additionalInfo: ["test": "value"]
        )

        let error = BaseRunarError.serviceError("Test error", component: .node, context: context)
        XCTAssertEqual(error.code, "SERVICE_ERROR")
        XCTAssertEqual(error.message, "Test error")
        XCTAssertEqual(error.component, .node)
        XCTAssertEqual(error.context.nodeId, "test-node")
        XCTAssertEqual(error.context.servicePath, "test/service")
    }

    func testTopicPath() {
        // Test topic path parsing and manipulation
        let path1 = TopicPath.parse("net:service/method")
        XCTAssertEqual(path1.networkId, "net")
        XCTAssertEqual(path1.segments, ["service", "method"])

        let path2 = TopicPath.parse("default:topic")
        XCTAssertEqual(path2.networkId, "default")

        let path3 = TopicPath(networkId: "test", segments: ["a", "b", "c"])
        XCTAssertEqual(path3.asString(), "test:a/b/c")
        XCTAssertFalse(path3.isPattern) // No wildcards, not a pattern
    }
}
