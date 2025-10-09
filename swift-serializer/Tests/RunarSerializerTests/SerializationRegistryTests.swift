import RunarSerializer
import XCTest

@testable import RunarSerializer

final class SerializationRegistryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clear the registry! before each test
        Task {
            await SerializationRegistry.shared.clearAll()
        }
    }

    override func tearDown() {
        super.tearDown()
        // Clear the registry! after each test
        Task {
            await SerializationRegistry.shared.clearAll()
        }
    }

    // MARK: - Basic Functionality Tests

    func testRegisterAndRetrieveWireName() async {
        // Test basic wire name registration and retrieval
        await SerializationRegistry.shared.registerWireName(for: TestStruct.self, wireName: "test_struct")

        let wireName = await SerializationRegistry.shared.wireName(for: "TestStruct")
        XCTAssertEqual(wireName, "test_struct")
    }

    func testWireNameNotFound() async {
        // Test behavior when wire name is not found
        let wireName = await SerializationRegistry.shared.wireName(for: "NonExistentType")
        XCTAssertNil(wireName)
    }

    func testRegisterAndRetrieveDecoder() async {
        // Test decoder registration and retrieval
        await SerializationRegistry.shared.registerDecoder(for: "test_struct") { _ in
            TestStruct(id: 789, name: "decoded")
        }

        let decoder = await SerializationRegistry.shared.decoder(for: "test_struct")
        XCTAssertNotNil(decoder)

        // Test the decoder works
        let testData = Data([1, 2, 3])
        let result = try! decoder!(testData)
        XCTAssertTrue(result is TestStruct)

        guard let testStruct = result as? TestStruct else {
            XCTFail("Expected TestStruct")
            return
        }
        XCTAssertEqual(testStruct.id, 789)
        XCTAssertEqual(testStruct.name, "decoded")
    }

    func testClearAll() async {
        // Test clearing all registrations
        await SerializationRegistry.shared.registerWireName(for: TestStruct.self, wireName: "test_struct")

        // Verify registration exists
        let wireName = await SerializationRegistry.shared.wireName(for: "TestStruct")
        XCTAssertNotNil(wireName)

        // Clear all
        await SerializationRegistry.shared.clearAll()

        // Verify registration is gone
        let wireNameAfterClear = await SerializationRegistry.shared.wireName(for: "TestStruct")
        XCTAssertNil(wireNameAfterClear)
    }
}

// MARK: - Test Types (Real Types, No Mocks)

struct TestStruct: Codable, Equatable {
    let id: Int
    let name: String
}
