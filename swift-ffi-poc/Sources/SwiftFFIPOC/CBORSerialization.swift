import Foundation
import SwiftCBOR

/// CBOR serialization utilities for FFI communication
public enum CBORSerialization {
    
    /// Serialize a SampleObject to CBOR bytes
    /// - Parameter object: The SampleObject to serialize
    /// - Returns: CBOR bytes as Data
    /// - Throws: CBOR encoding errors
    public static func serialize(_ object: SampleObject) throws -> Data {
        // Convert SampleObject to CBOR using SwiftCBOR
        let cbor = try object.toCBOR()
        let bytes = cbor.encode()
        return Data(bytes)
    }
    
    /// Deserialize CBOR bytes to a SampleObject
    /// - Parameter data: CBOR bytes as Data
    /// - Returns: The deserialized SampleObject
    /// - Throws: CBOR decoding errors
    public static func deserialize(_ data: Data) throws -> SampleObject {
        let bytes = Array(data)
        guard let cbor = try? CBOR.decode(bytes) else {
            throw CBORError.invalidFormat("Failed to decode CBOR data")
        }
        return try SampleObject.fromCBOR(cbor)
    }
    
    /// Convert Data to UnsafePointer<UInt8> for FFI calls
    /// - Parameter data: The data to convert
    /// - Returns: A tuple containing the pointer and length
    /// - Note: The caller is responsible for ensuring the data remains valid during the FFI call
    public static func toFFIPointer(_ data: Data) -> (UnsafePointer<UInt8>, UInt) {
        return (data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress! }, UInt(data.count))
    }
    
    /// Convert String to UnsafePointer<CChar> for FFI calls
    /// - Parameter string: The string to convert
    /// - Returns: A tuple containing the pointer and length
    /// - Note: The caller is responsible for ensuring the string remains valid during the FFI call
    public static func toFFIPointer(_ string: String) -> (UnsafePointer<CChar>, UInt) {
        let cString = string.cString(using: .utf8)!
        return (UnsafePointer(cString), UInt(cString.count - 1)) // -1 to exclude null terminator
    }
    
    /// Safely convert UnsafePointer<UInt8> back to Data
    /// - Parameters:
    ///   - pointer: Pointer to the data
    ///   - length: Length of the data
    /// - Returns: Data object
    public static func fromFFIPointer(_ pointer: UnsafePointer<UInt8>, length: UInt) -> Data {
        return Data(bytes: pointer, count: Int(length))
    }
    
    /// Safely convert UnsafePointer<CChar> back to String
    /// - Parameter pointer: Pointer to the C string
    /// - Returns: String object
    public static func fromFFIPointer(_ pointer: UnsafePointer<CChar>) -> String {
        return String(cString: pointer)
    }
}

// MARK: - SampleObject CBOR Extensions

extension SampleObject {
    
    /// Convert SampleObject to CBOR
    /// - Returns: CBOR representation
    /// - Throws: Encoding errors
    fileprivate func toCBOR() throws -> CBOR {
        var map: [CBOR: CBOR] = [:]
        
        map[CBOR.utf8String("id")] = CBOR.unsignedInt(id)
        map[CBOR.utf8String("name")] = CBOR.utf8String(name)
        map[CBOR.utf8String("timestamp")] = CBOR.unsignedInt(timestamp)
        
        // Convert metadata dictionary
        var metadataMap: [CBOR: CBOR] = [:]
        for (key, value) in metadata {
            metadataMap[CBOR.utf8String(key)] = CBOR.utf8String(value)
        }
        map[CBOR.utf8String("metadata")] = CBOR.map(metadataMap)
        
        // Convert values array
        let valuesArray = values.map { CBOR.double($0) }
        map[CBOR.utf8String("values")] = CBOR.array(valuesArray)
        
        return CBOR.map(map)
    }
    
    /// Create SampleObject from CBOR
    /// - Parameter cbor: CBOR representation
    /// - Returns: SampleObject instance
    /// - Throws: Decoding errors
    fileprivate static func fromCBOR(_ cbor: CBOR) throws -> SampleObject {
        guard case let .map(map) = cbor else {
            throw CBORError.invalidFormat("Expected CBOR map")
        }
        
        // Extract id
        guard let idCBOR = map[CBOR.utf8String("id")],
              case let .unsignedInt(id) = idCBOR else {
            throw CBORError.invalidFormat("Invalid or missing 'id' field")
        }
        
        // Extract name
        guard let nameCBOR = map[CBOR.utf8String("name")],
              case let .utf8String(name) = nameCBOR else {
            throw CBORError.invalidFormat("Invalid or missing 'name' field")
        }
        
        // Extract timestamp
        guard let timestampCBOR = map[CBOR.utf8String("timestamp")],
              case let .unsignedInt(timestamp) = timestampCBOR else {
            throw CBORError.invalidFormat("Invalid or missing 'timestamp' field")
        }
        
        // Extract metadata
        guard let metadataCBOR = map[CBOR.utf8String("metadata")],
              case let .map(metadataMap) = metadataCBOR else {
            throw CBORError.invalidFormat("Invalid or missing 'metadata' field")
        }
        
        var metadata: [String: String] = [:]
        for (key, value) in metadataMap {
            guard case let .utf8String(keyStr) = key,
                  case let .utf8String(valueStr) = value else {
                throw CBORError.invalidFormat("Invalid metadata key-value pair")
            }
            metadata[keyStr] = valueStr
        }
        
        // Extract values
        guard let valuesCBOR = map[CBOR.utf8String("values")],
              case let .array(valuesArray) = valuesCBOR else {
            throw CBORError.invalidFormat("Invalid or missing 'values' field")
        }
        
        var values: [Double] = []
        for valueCBOR in valuesArray {
            guard case let .double(value) = valueCBOR else {
                throw CBORError.invalidFormat("Invalid value in values array")
            }
            values.append(value)
        }
        
        return SampleObject(
            id: id,
            name: name,
            timestamp: timestamp,
            metadata: metadata,
            values: values
        )
    }
}

// MARK: - CBOR Error

/// CBOR encoding/decoding errors
public enum CBORError: Error, LocalizedError {
    case invalidFormat(String)
    
    public var errorDescription: String? {
        return "CBOR Error: \(message)"
    }
    
    private var message: String {
        switch self {
        case .invalidFormat(let description):
            return description
        }
    }
}
