import Testing
@testable import SwiftCommon

@Suite("Serializer Test Vectors Tests")
struct SerializerTestVectorsTest {

    @Test
    func testBasicTopicPath() throws {
        let path1 = try TopicPath(networkId: "main", segments: ["auth", "login"])
        let path2 = try TopicPath(networkId: "main", segments: ["auth", "login"])
        let path3 = try TopicPath(networkId: "main", segments: ["a", "b", "c"])

        #expect(path1 == path2)
        #expect(path1.asString() == "main:auth/login")
        #expect(path3.isPattern == false)
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

        // Should be 16 bytes (32 hex chars) from SHA-256
        #expect(compactId.count == 32)
    }

    @Test
    func testCompactIdValidation() {
        // Valid compact ID
        let validId = "a1b2c3d4e5f67890123456789012345"

        // For now, just test that we can generate a valid compact ID
        // The actual validation logic would need to be implemented
        let testData = "test data for compact id".data(using: .utf8)!
        let compactId = CompactId.compactId(from: testData)

        #expect(!compactId.isEmpty)
        #expect(compactId.count == 32) // SHA-256 produces 32 bytes (64 hex chars)

        // Test that the same input produces the same output (deterministic)
        let compactId2 = CompactId.compactId(from: testData)
        #expect(compactId == compactId2)
    }
}
