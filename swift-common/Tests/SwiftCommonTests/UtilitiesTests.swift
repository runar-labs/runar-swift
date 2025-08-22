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
    func testCompactIdGeneration() throws {
        let testData = "test data for compact id generation".data(using: .utf8)!
        let compactId = CompactId.compactId(from: testData)

        // Compact ID should be a valid Base32hex string (no padding)
        #expect(!compactId.isEmpty)
        #expect(compactId.allSatisfy { $0.isHexDigit || $0.isLetter })
        #expect(compactId == compactId.lowercased()) // Should be lowercase

        // Should be deterministic - same input gives same output
        let compactId2 = CompactId.compactId(from: testData)
        #expect(compactId == compactId2)

        // Should be 16 bytes encoded as Base32hex (26 chars) from SHA-256
        #expect(compactId.count == 26)
    }

    @Test
    func testCompactIdValidation() {
        // Valid compact ID (for reference, not used in current test)
        _ = "a1b2c3d4e5f67890123456789012345"

        // For now, just test that we can generate a valid compact ID
        // The actual validation logic would need to be implemented
        let testData = "test data for compact id".data(using: .utf8)!
        let compactId = CompactId.compactId(from: testData)

        #expect(!compactId.isEmpty)
        #expect(compactId.count == 26) // SHA-256 first 16 bytes encoded as Base32hex (26 chars)

        // Test that the same input produces the same output (deterministic)
        let compactId2 = CompactId.compactId(from: testData)
        #expect(compactId == compactId2)
    }

    @Test
    func testCompactIdNotEmpty() {
        // Test with typical public key size (97 bytes for secp256r1)
        let pub = Data(repeating: 0x42, count: 97)
        let id = CompactId.compactId(from: pub)
        #expect(!id.isEmpty)
    }
}
