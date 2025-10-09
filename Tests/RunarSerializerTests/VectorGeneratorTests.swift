import XCTest
import RunarSerializer
import Foundation

final class VectorGeneratorTests: XCTestCase {
    
    let outputDir = URL(fileURLWithPath: "target/serializer-vectors-swift")
    
    override func setUp() {
        super.setUp()
        // Create output directory if it doesn't exist
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }
    
    func testGeneratePrimitiveVectors() throws {
        // Generate primitive type test vectors
        try generatePrimitiveString()
        try generatePrimitiveBool()
        try generatePrimitiveI64()
        try generatePrimitiveU64()
        try generateBytes()
        try generateJSON()
        try generateListAny()
        try generateMapAny()
        try generateListI64()
        try generateMapStringI64()
        try generateStructPlain()
        
        print("✅ All test vectors generated successfully")
    }
    
    private func generatePrimitiveString() throws {
        let value = AnyValue.primitive("hello")
        let data = try value.serialize()
        try data.write(to: outputDir.appendingPathComponent("prim_string.bin"))
    }
    
    private func generatePrimitiveBool() throws {
        let value = AnyValue.primitive(true)
        let data = try value.serialize()
        try data.write(to: outputDir.appendingPathComponent("prim_bool.bin"))
    }
    
    private func generatePrimitiveI64() throws {
        let value = AnyValue.primitive(42)
        let data = try value.serialize()
        try data.write(to: outputDir.appendingPathComponent("prim_i64.bin"))
    }
    
    private func generatePrimitiveU64() throws {
        let value = AnyValue.primitive(UInt(7))
        let data = try value.serialize()
        try data.write(to: outputDir.appendingPathComponent("prim_u64.bin"))
    }
    
    private func generateBytes() throws {
        let value = AnyValue.bytes(Data([1, 2, 3]))
        let data = try value.serialize()
        try data.write(to: outputDir.appendingPathComponent("bytes.bin"))
    }
    
    private func generateJSON() throws {
        let jsonObject: [String: Any] = ["a": 1, "b": [true, "x"]]
        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let value = AnyValue.json(jsonString)
        let data = try value.serialize()
        try data.write(to: outputDir.appendingPathComponent("json.bin"))
    }
    
    private func generateListAny() throws {
        let list = AnyValue.list([
            AnyValue.primitive(1),
            AnyValue.primitive("two")
        ])
        let data = try list.serialize()
        try data.write(to: outputDir.appendingPathComponent("list_any.bin"))
    }
    
    private func generateMapAny() throws {
        let map = AnyValue.map([
            "x": AnyValue.primitive(10),
            "y": AnyValue.primitive("ten")
        ])
        let data = try map.serialize()
        try data.write(to: outputDir.appendingPathComponent("map_any.bin"))
    }
    
    private func generateListI64() throws {
        let list = AnyValue.list([1, 2, 3])
        let data = try list.serialize()
        try data.write(to: outputDir.appendingPathComponent("list_i64.bin"))
    }
    
    private func generateMapStringI64() throws {
        let map = AnyValue.map(["a": 1, "b": 2])
        let data = try map.serialize()
        try data.write(to: outputDir.appendingPathComponent("map_string_i64.bin"))
    }
    
    private func generateStructPlain() throws {
        // For now, we'll create a simple struct-like structure
        // This would need to be updated when we have proper struct support
        let structData = AnyValue.map([
            "id": AnyValue.primitive("u1"),
            "name": AnyValue.primitive("Alice")
        ])
        let data = try structData.serialize()
        try data.write(to: outputDir.appendingPathComponent("struct_plain.bin"))
    }
}
