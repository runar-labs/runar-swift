import Foundation

/// Sample data object for FFI POC testing
/// Matches the Rust side SampleObject structure
public struct SampleObject: Codable, Equatable {
    public let id: UInt64
    public let name: String
    public let timestamp: UInt64
    public let metadata: [String: String]
    public let values: [Double]
    
    public init(
        id: UInt64,
        name: String,
        timestamp: UInt64,
        metadata: [String: String],
        values: [Double]
    ) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.metadata = metadata
        self.values = values
    }
    
    /// Create a sample object with current timestamp
    public static func createSample(
        id: UInt64 = UInt64.random(in: 1...UInt64.max),
        name: String = "Sample Object",
        metadata: [String: String] = [:],
        values: [Double] = [1.0, 2.0, 3.0]
    ) -> SampleObject {
        return SampleObject(
            id: id,
            name: name,
            timestamp: UInt64(Date().timeIntervalSince1970),
            metadata: metadata,
            values: values
        )
    }
    
    /// Create an error object for testing error handling
    public static func createErrorObject() -> SampleObject {
        return SampleObject(
            id: 0,
            name: "ERROR",
            timestamp: UInt64(Date().timeIntervalSince1970),
            metadata: ["error_test": "true"],
            values: []
        )
    }
}
