import Foundation
import SwiftCommon
import Testing

@Suite("Utilities Tests")
struct UtilitiesTest {

    @Test
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

        // Note: critical() method was removed from the cleaned up logger
        // Test child logger creation - using the existing child() method
        let childLogger = logger.child(component: .registry)
        childLogger.info("Test child logger")
    }

    @Test
    func testErrorHandling() {
        // Test error creation and context
        let context = ErrorContext(
            nodeId: "test-node",
            servicePath: "test/service",
            additionalInfo: ["test": "value"]
        )

        let error = BaseRunarError.serviceError("Test error", component: .node, context: context)
        #expect(error.code == "SERVICE_ERROR")
        #expect(error.message == "Test error")
        #expect(error.component == .node)
        #expect(error.context.nodeId == "test-node")
        #expect(error.context.servicePath == "test/service")
    }

    @Test
    func testTopicPath() throws {
        // Test topic path parsing and manipulation
        let path1 = try TopicPath.parse("net:service/method")
        #expect(path1.networkId == "net")
        #expect(path1.segments == [.literal("service"), .literal("method")])

        let path2 = try TopicPath.parse("default:topic")
        #expect(path2.networkId == "default")

        let path3 = try TopicPath(networkId: "test", segments: ["a", "b", "c"])
        #expect(path3.asString() == "test:a/b/c")
        #expect(!path3.isPattern) // No wildcards, not a pattern
    }
}
