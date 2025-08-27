import Foundation

public extension AnyValue {
    @MainActor
    func toJSONObject() async throws -> Any {
        if isNull { return NSNull() }
        // Prefer registry converter by wire name
        if let converter = await SerializationRegistry.shared.jsonConverter(for: typeName) {
            return try await converter(self)
        }
        // Built-ins
        switch category {
        case .primitive:
            // Attempt known primitives
            switch typeName {
            case "string": return try await asType() as String
            case "bool": return try await asType() as Bool
            case "i64": return try await asType() as Int
            case "u64": return try await asType() as UInt
            case "f32": return try await asType() as Float
            case "f64": return try await asType() as Double
            default:
                throw SerializerError.serializationFailed("No JSON converter for primitive \(typeName)")
            }
        case .bytes:
            let data: Data = try await asType()
            return data.base64EncodedString()
        case .json:
            // Already CBOR of JSON, round-trip as Foundation object
            let s: String = try await asType()
            let obj = try JSONSerialization.jsonObject(with: Data(s.utf8))
            return obj
        case .list:
            if typeName == "list<any>" {
                let arr: [AnyValue] = try await asType()
                return try await arr.asyncMap { try await $0.toJSONObject() }
            }
            // Typed container must be decoded to Decodable first by caller; no generic fallback
            throw SerializerError.serializationFailed("No JSON converter for typed list \(typeName)")
        case .map:
            if typeName == "map<string,any>" {
                let dict: [String: AnyValue] = try await asType()
                var out: [String: Any] = [:]
                for (k, v) in dict {
                    out[k] = try await v.toJSONObject()
                }
                return out
            }
            throw SerializerError.serializationFailed("No JSON converter for typed map \(typeName)")
        case .struct:
            // Require a registered converter
            throw SerializerError.serializationFailed("No JSON converter for struct wire name \(typeName)")
        case .null:
            return NSNull()
        }
    }

    @MainActor
    func toJSONData(prettyPrinted: Bool = false) async throws -> Data {
        let obj = try await toJSONObject()
        let options: JSONSerialization.WritingOptions = prettyPrinted ? [.prettyPrinted] : []
        return try JSONSerialization.data(withJSONObject: obj, options: options)
    }

    @MainActor
    func toJSONString(prettyPrinted: Bool = false) async throws -> String {
        let data = try await toJSONData(prettyPrinted: prettyPrinted)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

@MainActor
private extension [AnyValue] {
    func asyncMap<T>(_ transform: @escaping @MainActor (AnyValue) async throws -> T) async throws -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            try await results.append(transform(element))
        }
        return results
    }
}
