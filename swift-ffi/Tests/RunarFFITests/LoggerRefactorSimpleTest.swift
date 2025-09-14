import XCTest
@testable import RunarFFI

@available(macOS 11.0, *)
final class LoggerRefactorSimpleTest: XCTestCase {
    
    func testLoggerErrorCodes() {
        // Test that new logger error codes are defined
        let loggerAlreadyInitialized = FFIError.loggerAlreadyInitialized("test")
        XCTAssertEqual(loggerAlreadyInitialized.errorCode, 1020)
        XCTAssertEqual(loggerAlreadyInitialized.errorDescription, "Logger already initialized: test")
        
        let loggerNodeIdAlreadySet = FFIError.loggerNodeIdAlreadySet("test")
        XCTAssertEqual(loggerNodeIdAlreadySet.errorCode, 1021)
        XCTAssertEqual(loggerNodeIdAlreadySet.errorDescription, "Logger node ID already set: test")
        
        let loggerInvalidNodeId = FFIError.loggerInvalidNodeId("test")
        XCTAssertEqual(loggerInvalidNodeId.errorCode, 1022)
        XCTAssertEqual(loggerInvalidNodeId.errorDescription, "Invalid logger node ID: test")
        
        let loggerInvalidLevel = FFIError.loggerInvalidLevel("test")
        XCTAssertEqual(loggerInvalidLevel.errorCode, 1023)
        XCTAssertEqual(loggerInvalidLevel.errorDescription, "Invalid logger level: test")
    }
    
    func testErrorCodeMapping() {
        // Test that error codes map correctly
        let error1 = FFIError(code: 1020, message: "test1")
        if case .loggerAlreadyInitialized(let msg) = error1 {
            XCTAssertEqual(msg, "test1")
        } else {
            XCTFail("Expected loggerAlreadyInitialized error")
        }
        
        let error2 = FFIError(code: 1021, message: "test2")
        if case .loggerNodeIdAlreadySet(let msg) = error2 {
            XCTAssertEqual(msg, "test2")
        } else {
            XCTFail("Expected loggerNodeIdAlreadySet error")
        }
        
        let error3 = FFIError(code: 1022, message: "test3")
        if case .loggerInvalidNodeId(let msg) = error3 {
            XCTAssertEqual(msg, "test3")
        } else {
            XCTFail("Expected loggerInvalidNodeId error")
        }
        
        let error4 = FFIError(code: 1023, message: "test4")
        if case .loggerInvalidLevel(let msg) = error4 {
            XCTAssertEqual(msg, "test4")
        } else {
            XCTFail("Expected loggerInvalidLevel error")
        }
    }
    
    func testCANodeCreationWithoutLogger() throws {
        // Test that CA Node can be created without logger parameter
        let caNode = try CANode.create()
        XCTAssertNotNil(caNode)
        XCTAssertNotNil(caNode.ffiHandle)
    }
}
