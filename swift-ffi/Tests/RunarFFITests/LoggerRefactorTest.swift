import XCTest
@testable import RunarFFI

@available(macOS 11.0, *)
final class LoggerRefactorTest: XCTestCase {
    
    func testLoggerLevelSetting() throws {
        // Test setting logger level to Debug (4)
        XCTAssertNoThrow(try KeysFFI.setLoggerLevel(4))
        
        // Test setting logger level to Info (2)
        XCTAssertNoThrow(try KeysFFI.setLoggerLevel(2))
        
        // Test setting logger level to Error (0)
        XCTAssertNoThrow(try KeysFFI.setLoggerLevel(0))
    }
    
    func testLoggerNodeIdSetting() throws {
        // Test setting node ID
        XCTAssertNoThrow(try KeysFFI.setLoggerNodeId("test-node-123"))
        
        // Test setting another node ID
        XCTAssertNoThrow(try KeysFFI.setLoggerNodeId("another-node-456"))
    }
    
    func testCANodeCreationWithoutLogger() throws {
        // Test that CA Node can be created without logger parameter
        let caNode = try CANode.create()
        XCTAssertNotNil(caNode)
        XCTAssertNotNil(caNode.ffiHandle)
    }
    
    func testCAServerCreationWithoutLogger() throws {
        // Test that CA Server can be created without logger parameter
        let caNode = try CANode.create()
        let sharedCANode = try caNode.createShared()
        
        let config = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test_network",
            rateLimitPerMinute: 5,
            rateLimitPerHour: 30
        )
        
        let server = try CAServer.create(config: config, sharedCaNode: sharedCANode)
        XCTAssertNotNil(server)
    }
    
    func testLoggerFunctionsWork() throws {
        // Test that logger functions can be called without errors
        XCTAssertNoThrow(try KeysFFI.setLoggerLevel(2)) // Info level
        XCTAssertNoThrow(try KeysFFI.setLoggerNodeId("test-node-123"))
        
        // Test that we can call them multiple times
        XCTAssertNoThrow(try KeysFFI.setLoggerLevel(4)) // Debug level
        XCTAssertNoThrow(try KeysFFI.setLoggerNodeId("another-node-456"))
    }
    
    func testLoggerErrorCodes() {
        // Test that new logger error codes are defined
        let loggerAlreadyInitialized = FFIError.loggerAlreadyInitialized("test")
        XCTAssertEqual(loggerAlreadyInitialized.errorCode, 1020)
        
        let loggerNodeIdAlreadySet = FFIError.loggerNodeIdAlreadySet("test")
        XCTAssertEqual(loggerNodeIdAlreadySet.errorCode, 1021)
        
        let loggerInvalidNodeId = FFIError.loggerInvalidNodeId("test")
        XCTAssertEqual(loggerInvalidNodeId.errorCode, 1022)
        
        let loggerInvalidLevel = FFIError.loggerInvalidLevel("test")
        XCTAssertEqual(loggerInvalidLevel.errorCode, 1023)
    }
}
