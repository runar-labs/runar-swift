import XCTest
import RunarSerializer
import Foundation

final class CrossLangVectorsTests: XCTestCase {
    
    @MainActor
    func testLoadRustVectors_primitivesAndContainers() async throws {
        let base = URL(fileURLWithPath: "/Users/rafael/dev/runar-swift/runar-rust/target/serializer-vectors")
        // primitives
        do {
            let sData = try Data(contentsOf: base.appendingPathComponent("prim_string.bin"))
            let v = try AnyValue.deserialize(sData)
            let s: String = try await v.asType()
            XCTAssertEqual(s, "hello")
        }
        do {
            let bData = try Data(contentsOf: base.appendingPathComponent("prim_bool.bin"))
            let v = try AnyValue.deserialize(bData)
            let b: Bool = try await v.asType()
            XCTAssertEqual(b, true)
        }
        do {
            let iData = try Data(contentsOf: base.appendingPathComponent("prim_i64.bin"))
            let v = try AnyValue.deserialize(iData)
            let i: Int64 = try await v.asType()
            XCTAssertEqual(i, 42)
        }
        do {
            let uData = try Data(contentsOf: base.appendingPathComponent("prim_u64.bin"))
            let v = try AnyValue.deserialize(uData)
            let u: UInt64 = try await v.asType()
            XCTAssertEqual(u, 7)
        }
        // bytes
        do {
            let d = try Data(contentsOf: base.appendingPathComponent("bytes.bin"))
            let v = try AnyValue.deserialize(d)
            let bytes: Data = try await v.asType()
            XCTAssertEqual(bytes, Data([1, 2, 3]))
        }
        // json
        do {
            let d = try Data(contentsOf: base.appendingPathComponent("json.bin"))
            let v = try AnyValue.deserialize(d)
            let obj = try await v.toJSONObject() as? [String: Any]
            XCTAssertNotNil(obj)
            XCTAssertEqual(obj?["a"] as? NSNumber, 1)
            let b = obj?["b"] as? [Any]
            XCTAssertEqual(b?.count, 2)
        }
        // list<any>
        do {
            let d = try Data(contentsOf: base.appendingPathComponent("list_any.bin"))
            let v = try AnyValue.deserialize(d)
            let arr: [AnyValue] = try await v.asType()
            XCTAssertEqual(arr.count, 2)
            let first: Int64 = try await arr[0].asType()
            let second: String = try await arr[1].asType()
            XCTAssertEqual(first, 1)
            XCTAssertEqual(second, "two")
        }
        // map<string,any>
        do {
            let d = try Data(contentsOf: base.appendingPathComponent("map_any.bin"))
            let v = try AnyValue.deserialize(d)
            let dict: [String: AnyValue] = try await v.asType()
            let x: Int64 = try await dict["x"]!.asType()
            let y: String = try await dict["y"]!.asType()
            XCTAssertEqual(x, 10)
            XCTAssertEqual(y, "ten")
        }
        // list<i64>
        do {
            let d = try Data(contentsOf: base.appendingPathComponent("list_i64.bin"))
            let v = try AnyValue.deserialize(d)
            let arr: [Int64] = try await v.asType()
            XCTAssertEqual(arr, [1, 2, 3])
        }
        // map<string,i64>
        do {
            let d = try Data(contentsOf: base.appendingPathComponent("map_string_i64.bin"))
            let v = try AnyValue.deserialize(d)
            let dict: [String: Int64] = try await v.asType()
            XCTAssertEqual(dict["a"], 1)
            XCTAssertEqual(dict["b"], 2)
        }
    }
}
