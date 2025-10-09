import Foundation
import RunarSerializer
import SwiftCBOR

// MARK: - Rust Vector Validation

// Validates that Swift can read and understand Rust-generated test vectors

enum ValidationError: Error, LocalizedError {
    case fileNotFound(String)
    case deserializationFailed(String)
    case validationFailed(String, String)

    var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            "File not found: \(path)"
        case let .deserializationFailed(message):
            "Deserialization failed: \(message)"
        case let .validationFailed(expected, actual):
            "Validation failed - Expected: \(expected), Actual: \(actual)"
        }
    }
}

enum RustVectorValidator {
    static func validateAll() throws {
        print("🔬 Cross-Platform Serializer Validation (Swift reading Rust)")
        print("==========================================================")

        // Check directories exist
        try checkDirectories()

        print("\n🚀 Running validation tests...")

        let tests = [
            validatePrimitiveString,
            validatePrimitiveBool,
            validatePrimitiveI64,
            validatePrimitiveU64,
            validateBytes,
            validateJSON,
            validateListAny,
            validateMapAny,
            validateListI64,
            validateMapStringI64,
            validateStructPlain,
        ]

        var passed = 0
        var failed = 0

        for test in tests {
            do {
                try test()
                passed += 1
            } catch {
                print("❌ Test failed: \(error.localizedDescription)")
                failed += 1
            }
        }

        print("\n📊 Validation Results")
        print("===================")
        print("✅ Passed: \(passed)")
        print("❌ Failed: \(failed)")
        let successRate = Double(passed) / Double(passed + failed) * 100.0
        print("📈 Success Rate: \(String(format: "%.1f", successRate))%")

        if failed == 0 {
            print("\n🎉 All validations passed! Swift can read Rust serializer output!")
        } else {
            print("\n⚠️  Some validations failed. Check the output above for details.")
            throw ValidationError.validationFailed("All tests", "Some failed")
        }
    }

    private static func checkDirectories() throws {
        let rustDir = URL(fileURLWithPath: "runar-rust/target/serializer-vectors")
        let swiftDir = URL(fileURLWithPath: "target/serializer-vectors-swift")

        var isDirectory: ObjCBool = false

        if !FileManager.default.fileExists(atPath: rustDir.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            throw ValidationError.fileNotFound("Rust test vectors directory: \(rustDir.path)")
        }

        if !FileManager.default.fileExists(atPath: swiftDir.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            print("⚠️  Swift test vectors directory not found: \(swiftDir.path). This is expected when only validating Rust output.")
        }

        print("📁 Found test vector directories:")
        print("   Rust:  \(rustDir.path)")
        print("   Swift: \(swiftDir.path) (for reference)")
    }

    private static func readRustVector(named name: String) throws -> Data {
        let url = URL(fileURLWithPath: "runar-rust/target/serializer-vectors/\(name).bin")
        return try Data(contentsOf: url)
    }

    private static func validatePrimitiveString() throws {
        print("🔍 Validating primitive string...")
        let rustData = try readRustVector(named: "prim_string")

        // Deserialize using Swift AnyValue
        let value = try AnyValue.deserialize(rustData)

        guard case .primitive = value.category else {
            throw ValidationError.validationFailed("primitive", String(describing: value.category))
        }

        // For now, just check that it deserializes successfully
        // TODO: Add proper primitive value extraction when API is available
        print("✅ String validation passed (deserialized successfully)")
    }

    private static func validatePrimitiveBool() throws {
        print("🔍 Validating primitive bool...")
        let rustData = try readRustVector(named: "prim_bool")
        let value = try AnyValue.deserialize(rustData)

        guard case .primitive = value.category else {
            throw ValidationError.validationFailed("primitive", String(describing: value.category))
        }

        print("✅ Bool validation passed (deserialized successfully)")
    }

    private static func validatePrimitiveI64() throws {
        print("🔍 Validating primitive i64...")
        let rustData = try readRustVector(named: "prim_i64")
        let value = try AnyValue.deserialize(rustData)

        guard case .primitive = value.category else {
            throw ValidationError.validationFailed("primitive", String(describing: value.category))
        }

        print("✅ i64 validation passed (deserialized successfully)")
    }

    private static func validatePrimitiveU64() throws {
        print("🔍 Validating primitive u64...")
        let rustData = try readRustVector(named: "prim_u64")
        let value = try AnyValue.deserialize(rustData)

        guard case .primitive = value.category else {
            throw ValidationError.validationFailed("primitive", String(describing: value.category))
        }

        print("✅ u64 validation passed (deserialized successfully)")
    }

    private static func validateBytes() throws {
        print("🔍 Validating bytes...")
        let rustData = try readRustVector(named: "bytes")
        let value = try AnyValue.deserialize(rustData)

        guard case .bytes = value.category else {
            throw ValidationError.validationFailed("bytes", String(describing: value.category))
        }

        print("✅ Bytes validation passed (deserialized successfully)")
    }

    private static func validateJSON() throws {
        print("🔍 Validating JSON...")
        let rustData = try readRustVector(named: "json")
        let value = try AnyValue.deserialize(rustData)

        guard case .json = value.category else {
            throw ValidationError.validationFailed("json", String(describing: value.category))
        }

        // For JSON validation, we just check that it deserializes successfully
        // The exact JSON content validation would require JSON parsing
        print("✅ JSON validation passed (deserialized successfully)")
    }

    private static func validateListAny() throws {
        print("🔍 Validating heterogeneous list...")
        let rustData = try readRustVector(named: "list_any")
        let value = try AnyValue.deserialize(rustData)

        guard case .list = value.category else {
            throw ValidationError.validationFailed("list", String(describing: value.category))
        }

        print("✅ Heterogeneous list validation passed (deserialized successfully)")
    }

    private static func validateMapAny() throws {
        print("🔍 Validating heterogeneous map...")
        let rustData = try readRustVector(named: "map_any")
        let value = try AnyValue.deserialize(rustData)

        guard case .map = value.category else {
            throw ValidationError.validationFailed("map", String(describing: value.category))
        }

        print("✅ Heterogeneous map validation passed (deserialized successfully)")
    }

    private static func validateListI64() throws {
        print("🔍 Validating typed i64 list...")
        let rustData = try readRustVector(named: "list_i64")
        let value = try AnyValue.deserialize(rustData)

        guard case .list = value.category else {
            throw ValidationError.validationFailed("list", String(describing: value.category))
        }

        print("✅ Typed i64 list validation passed (deserialized successfully)")
    }

    private static func validateMapStringI64() throws {
        print("🔍 Validating typed string->i64 map...")
        let rustData = try readRustVector(named: "map_string_i64")
        let value = try AnyValue.deserialize(rustData)

        guard case .map = value.category else {
            throw ValidationError.validationFailed("map", String(describing: value.category))
        }

        print("✅ Typed string->i64 map validation passed (deserialized successfully)")
    }

    private static func validateStructPlain() throws {
        print("🔍 Validating plain struct...")
        let rustData = try readRustVector(named: "struct_plain")
        let value = try AnyValue.deserialize(rustData)

        guard case .struct = value.category else {
            throw ValidationError.validationFailed("struct", String(describing: value.category))
        }

        print("✅ Plain struct validation passed (deserialized successfully)")
    }
}
