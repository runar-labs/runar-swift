import Foundation
import SwiftCBOR

enum WireNames {
    static let primitiveWireSet: Set<String> = [
        "string", "bool", "bytes", "char",
        "i8", "i16", "i32", "i64",
        "u8", "u16", "u32", "u64",
        "f32", "f64",
    ]

    static func isValidPrimitiveWireName(_ name: String) -> Bool {
        primitiveWireSet.contains(name)
    }

    static func primitiveWireName(_ type: Any.Type) -> String? {
        switch type {
        case is String.Type: "string"
        case is Bool.Type: "bool"
        case is Data.Type: "bytes"
        case is Character.Type: "char"
        case is Int8.Type: "i8"
        case is Int16.Type: "i16"
        case is Int32.Type: "i32"
        case is Int64.Type: "i64"
        case is UInt8.Type: "u8"
        case is UInt16.Type: "u16"
        case is UInt32.Type: "u32"
        case is UInt64.Type: "u64"
        case is Float.Type: "f32"
        case is Double.Type: "f64"
        case is Int.Type: "i64" // Apple 64-bit normalization
        case is UInt.Type: "u64" // Apple 64-bit normalization
        default:
            nil
        }
    }

    static func listWireName(_ elem: Any.Type) -> String {
        if let primitive = primitiveWireName(elem) {
            return "list<\(primitive)>"
        }
        // Use new SerializationRegistry for wire name lookup
        let swiftName = String(describing: elem)
        let wire = SerializationRegistry.shared.wireNameSync(for: swiftName) ?? swiftName
        return "list<\(wire)>"
    }

    static func mapWireName(_ elem: Any.Type) -> String {
        if let primitive = primitiveWireName(elem) {
            return "map<string,\(primitive)>"
        }
        // Use new SerializationRegistry for wire name lookup
        let swiftName = String(describing: elem)
        let wire = SerializationRegistry.shared.wireNameSync(for: swiftName) ?? swiftName
        return "map<string,\(wire)>"
    }
}

enum WireNameParser {
    static func parseList(_ wire: String) -> String? {
        guard wire.hasPrefix("list<"), wire.hasSuffix(">") else { return nil }
        let inner = String(wire.dropFirst(5).dropLast(1))
        return inner
    }

    static func parseMap(_ wire: String) -> String? {
        guard wire.hasPrefix("map<string,"), wire.hasSuffix(">") else { return nil }
        let inner = String(wire.dropFirst("map<string,".count).dropLast(1))
        return inner
    }
}

//     return result
// }

// Minimal CBOR->Foundation JSON converter for json category
func cborToFoundationJSON(_ cbor: CBOR) throws -> Any {
    switch cbor {
    case .null: return NSNull()
    case let .boolean(boolValue): return boolValue
    case let .unsignedInt(unsignedValue): return NSNumber(value: unsignedValue)
    case let .negativeInt(negativeValue): return NSNumber(value: -Int64(negativeValue) - 1)
    case let .utf8String(stringValue): return stringValue
    case let .double(doubleValue): return doubleValue
    case let .float(floatValue): return Double(floatValue)
    case let .map(mapEntries):
        var dict: [String: Any] = [:]
        for (key, value) in mapEntries {
            guard case let .utf8String(keyString) = key else { continue }
            dict[keyString] = try cborToFoundationJSON(value)
        }
        return dict
    case let .array(arrayElements):
        return try arrayElements.map { try cborToFoundationJSON($0) }
    case let .byteString(byteArray):
        // For JSON conversion policy in Swift, bytes become base64 string
        return Data(byteArray).base64EncodedString()
    default:
        throw SerializerError.deserializationFailed("Unsupported CBOR token in JSON conversion: \(cbor)")
    }
}
