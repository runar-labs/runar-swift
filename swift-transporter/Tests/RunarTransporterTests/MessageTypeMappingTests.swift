import XCTest
@testable import RunarTransporter

final class MessageTypeMappingTests: XCTestCase {
    func testParseSwiftStringDigits() throws {
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("1"), .discovery)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("2"), .heartbeat)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("3"), .announcement)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("4"), .handshake)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("5"), .request)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("6"), .response)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("7"), .event)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("8"), .error)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("9"), .nodeInfoUpdate)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("10"), .nodeInfoHandshakeResponse)
    }

    func testParseSwiftStringNames() throws {
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("Discovery"), .discovery)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("heartbeat"), .heartbeat)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("Handshake"), .handshake)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("request"), .request)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("Response"), .response)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("event"), .event)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("Error"), .error)
        XCTAssertEqual(try MessageTypeMapping.parseSwiftString("announcement"), .announcement)
    }

    func testToRustU32CoreTypes() throws {
        XCTAssertEqual(try MessageTypeMapping.toRustU32(.discovery), RustMessageType.discovery)
        XCTAssertEqual(try MessageTypeMapping.toRustU32(.heartbeat), RustMessageType.heartbeat)
        XCTAssertEqual(try MessageTypeMapping.toRustU32(.handshake), RustMessageType.handshake)
        XCTAssertEqual(try MessageTypeMapping.toRustU32(.request), RustMessageType.request)
        XCTAssertEqual(try MessageTypeMapping.toRustU32(.response), RustMessageType.response)
        XCTAssertEqual(try MessageTypeMapping.toRustU32(.event), RustMessageType.event)
        XCTAssertEqual(try MessageTypeMapping.toRustU32(.error), RustMessageType.error)
    }
    
    func testSwiftStringToRustU32() throws {
        XCTAssertEqual(try MessageTypeMapping.swiftStringToRustU32("4"), RustMessageType.handshake)
        XCTAssertEqual(try MessageTypeMapping.swiftStringToRustU32("5"), RustMessageType.request)
    }

    func testUnsupportedSwiftOnlyTypesThrow() {
        XCTAssertThrowsError(try MessageTypeMapping.toRustU32(.announcement))
        XCTAssertThrowsError(try MessageTypeMapping.toRustU32(.nodeInfoUpdate))
        XCTAssertThrowsError(try MessageTypeMapping.toRustU32(.nodeInfoHandshakeResponse))
    }

    func testUnknownStringThrows() {
        XCTAssertThrowsError(try MessageTypeMapping.parseSwiftString("UNKNOWN-XYZ"))
        XCTAssertThrowsError(try MessageTypeMapping.swiftStringToRustU32("42"))
    }
}


