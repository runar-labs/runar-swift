import Foundation
import SwiftCBOR

enum WireNames {
    static func primitiveWireName(_ type: Any.Type) -> String? {
        switch type {
        case is String.Type: return "string"
        case is Bool.Type: return "bool"
        case is Data.Type: return "bytes"
        case is Int8.Type: return "i8"
        case is Int16.Type: return "i16"
        case is Int32.Type: return "i32"
        case is Int64.Type: return "i64"
        case is UInt8.Type: return "u8"
        case is UInt16.Type: return "u16"
        case is UInt32.Type: return "u32"
        case is UInt64.Type: return "u64"
        case is Float.Type: return "f32"
        case is Double.Type: return "f64"
        case is Int.Type: return "i64" // Apple 64-bit normalization
        case is UInt.Type: return "u64" // Apple 64-bit normalization
        default:
            return nil
        }
    }

    static func listWireName(_ elem: Any.Type) -> String {
        if let primitive = primitiveWireName(elem) {
            return "list<\(primitive)>"
        }
        // Fallback to Swift name for now; will be replaced by registry wire names
        let swiftName = String(describing: elem)
        return "list<\(swiftName)>"
    }

    static func mapWireName(_ elem: Any.Type) -> String {
        if let primitive = primitiveWireName(elem) {
            return "map<string,\(primitive)>"
        }
        // Fallback to Swift name for now; will be replaced by registry wire names
        let swiftName = String(describing: elem)
        return "map<string,\(swiftName)>"
    }
}

// Minimal CBOR->Foundation JSON converter for json category
func cborToFoundationJSON(_ cbor: CBOR) throws -> Any {
    switch cbor {
    case .null: return NSNull()
    case let .boolean(b): return b
    case let .unsignedInt(u): return NSNumber(value: u)
    case let .negativeInt(n): return NSNumber(value: -Int64(n) - 1)
    case let .utf8String(s): return s
    case let .double(d): return d
    case let .float(f): return Double(f)
    case let .map(m):
        var dict: [String: Any] = [:]
        for (k, v) in m {
            guard case let .utf8String(key) = k else { continue }
            dict[key] = try cborToFoundationJSON(v)
        }
        return dict
    case let .array(arr):
        return try arr.map { try cborToFoundationJSON($0) }
    case let .byteString(b):
        // For JSON conversion policy in Swift, bytes become base64 string
        return Data(b).base64EncodedString()
    default:
        throw SerializerError.deserializationFailed("Unsupported CBOR token in JSON conversion: \(cbor)")
    }
}


