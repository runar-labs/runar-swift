import Foundation
import RunarSerializer

/// Swift equivalent of Rust's serializer_vectors.rs
/// Generates binary test data for cross-platform compatibility testing
enum SerializerTestVectors {
    private static let outputDir = "target/serializer-vectors-swift"

    /// Plain user struct matching Rust's PlainUser
    struct PlainUser: Codable, Sendable {
        let id: String
        let name: String
    }

    /// Test profile struct matching Rust's TestProfile
    struct TestProfile: Codable, Sendable {
        let id: String
        let secret: String
    }

    /// Generate all test vectors and write them to files
    static func generate() throws {
        try createOutputDirectory()

        print("Generating Swift serializer test vectors...")

        // Primitives
        try writePrimitiveString()
        try writePrimitiveBool()
        try writePrimitiveI64()
        try writePrimitiveU64()

        // Bytes
        try writeBytes()

        // JSON
        try writeJSON()

        // Heterogeneous collections
        try writeListAny()
        try writeMapAny()

        // Typed collections
        try writeListI64()
        try writeMapStringI64()

        // Plain struct
        try writeStructPlain()

        print("✅ Wrote Swift serializer vectors to \(outputDir)")
    }

    private static func createOutputDirectory() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
    }

    private static func writeBytes(toFile filename: String, data: Data) throws {
        let filePath = "\(outputDir)/\(filename)"
        try data.write(to: URL(fileURLWithPath: filePath))
        print("  Generated: \(filename)")
    }

    // MARK: - Primitive Tests

    private static func writePrimitiveString() throws {
        let value = AnyValue.primitive("hello")
        let data = try value.serialize(context: nil)
        try writeBytes(toFile: "prim_string.bin", data: data)
    }

    private static func writePrimitiveBool() throws {
        let value = AnyValue.primitive(true)
        let data = try value.serialize(context: nil)
        try writeBytes(toFile: "prim_bool.bin", data: data)
    }

    private static func writePrimitiveI64() throws {
        let value = AnyValue.primitive(Int64(42))
        let data = try value.serialize(context: nil)
        try writeBytes(toFile: "prim_i64.bin", data: data)
    }

    private static func writePrimitiveU64() throws {
        let value = AnyValue.primitive(UInt64(7))
        let data = try value.serialize(context: nil)
        try writeBytes(toFile: "prim_u64.bin", data: data)
    }

    // MARK: - Bytes Test

    private static func writeBytes() throws {
        let bytes = Data([1, 2, 3])
        let value = AnyValue.bytes(bytes)
        let data = try value.serialize(context: nil)
        try writeBytes(toFile: "bytes.bin", data: data)
    }

    // MARK: - JSON Test

    private static func writeJSON() throws {
        let jsonObject: [String: AnyValue] = [
            "a": .primitive(1),
            "b": .list([.primitive(true), .primitive("x")])
        ]
        let value = AnyValue.map(jsonObject)
        let data = try value.serialize(context: nil)
        try writeBytes(toFile: "json.bin", data: data)
    }

    // MARK: - Heterogeneous Collections

    private static func writeListAny() throws {
        let list = [
            AnyValue.primitive(Int64(1)),
            AnyValue.primitive("two")
        ]
        let value = AnyValue.list(list)
        let data = try value.serialize(context: nil)
        try writeBytes(toFile: "list_any.bin", data: data)
    }

    private static func writeMapAny() throws {
        let map: [String: AnyValue] = [
            "x": .primitive(Int64(10)),
            "y": .primitive("ten")
        ]
        let value = AnyValue.map(map)
        let data = try value.serialize(context: nil)
        try writeBytes(toFile: "map_any.bin", data: data)
    }

    // MARK: - Typed Collections

    private static func writeListI64() throws {
        let list = [AnyValue.primitive(Int64(1)), AnyValue.primitive(Int64(2)), AnyValue.primitive(Int64(3))]
        let value = AnyValue.list(list)
        let data = try value.serialize(context: nil)
        try writeBytes(toFile: "list_i64.bin", data: data)
    }

    private static func writeMapStringI64() throws {
        let map: [String: AnyValue] = [
            "a": .primitive(Int64(1)),
            "b": .primitive(Int64(2))
        ]
        let value = AnyValue.map(map)
        let data = try value.serialize(context: nil)
        try writeBytes(toFile: "map_string_i64.bin", data: data)
    }

    // MARK: - Struct Tests

    private static func writeStructPlain() throws {
        let user = PlainUser(id: "u1", name: "Alice")
        let value = AnyValue.struct(user)
        let data = try value.serialize(context: nil)
        try writeBytes(toFile: "struct_plain.bin", data: data)
    }
}

// Parse command line arguments
let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "generate"

do {
    switch command {
    case "generate":
        print("🔧 Generating Swift serializer test vectors...")
        try SerializerTestVectors.generate()
        print("✅ Successfully generated test vectors")

    case "validate-rust":
        print("🔍 Validating Rust-generated test vectors...")
        try RustVectorValidator.validateAll()
        print("✅ Successfully validated Rust vectors")

    case "validate-swift":
        print("🔍 Validating Swift-generated test vectors...")
        print("⚠️  Swift vector validation not yet implemented")

    default:
        print("❌ Unknown command: \(command)")
        print("Available commands:")
        print("  generate       - Generate Swift test vectors")
        print("  validate-rust  - Validate Rust vectors with Swift")
        print("  validate-swift - Validate Swift vectors (not implemented)")
        exit(1)
    }
} catch {
    print("❌ Error: \(error)")
    exit(1)
}
