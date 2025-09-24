@testable import RunarSerializer
import SwiftCBOR
import XCTest

final class BasicAnyValueTests: XCTestCase {
    func testNullValue() async throws {
        let nullValue = AnyValue.null()

        XCTAssertTrue(nullValue.isNull)
        XCTAssertEqual(nullValue.category, .null)
        XCTAssertEqual(nullValue.typeName, "null")

        // Test serialization
        let serialized = try await nullValue.serialize()
        XCTAssertEqual(serialized.count, 1)
        XCTAssertEqual(serialized[0], 0) // null category byte
    }

    func testPrimitiveString() async throws {
        let testString = "Hello, World!"
        let primitiveValue = AnyValue.primitive(testString)

        XCTAssertFalse(primitiveValue.isNull)
        XCTAssertEqual(primitiveValue.category, .primitive)
        XCTAssertEqual(primitiveValue.typeName, "string")

        // Test type retrieval
        do {
            let retrievedString: String = try await primitiveValue.asType()
            XCTAssertEqual(retrievedString, testString)
        } catch {
            XCTFail("Failed to get string value: \(error)")
        }

        // Test serialization
        let serialized = try await primitiveValue.serialize()
        XCTAssertFalse(serialized.isEmpty)
    }

    func testBytesValue() async throws {
        let testData = "Test bytes".data(using: .utf8)!
        let bytesValue = AnyValue.bytes(testData)

        XCTAssertFalse(bytesValue.isNull)
        XCTAssertEqual(bytesValue.category, .bytes)
        XCTAssertEqual(bytesValue.typeName, "bytes")

        // Test type retrieval
        do {
            let retrievedData: Data = try await bytesValue.asType()
            XCTAssertEqual(retrievedData, testData)
        } catch {
            XCTFail("Failed to get bytes value: \(error)")
        }

        // Test serialization
        let serialized = try await bytesValue.serialize()
        // Format: [category][encrypted][type_name_len][type_name][data]
        // For bytes: [5][0][5]["bytes"][actual_raw_data]
        XCTAssertGreaterThan(serialized.count, testData.count)
        let dataStart = 3 + 5 // category + encrypted + type_name_len + "bytes"
        let actualData = serialized[dataStart...]
        // Payload for bytes is raw
        XCTAssertEqual(Data(actualData), testData)
    }

    func testTypeMismatch() async {
        let testString = "Hello"
        let primitiveValue = AnyValue.primitive(testString)

        // Try to get as wrong type
        do {
            let _: Data = try await primitiveValue.asType()
            XCTFail("Should have thrown type mismatch error")
        } catch SerializerError.typeMismatch {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeserializeNull() {
        let nullData = Data([0]) // null category byte

        do {
            let deserialized = try AnyValue.deserialize(nullData)
            XCTAssertTrue(deserialized.isNull)
            XCTAssertEqual(deserialized.category, .null)
        } catch {
            XCTFail("Failed to deserialize null: \(error)")
        }
    }

    func testDeserializeEmptyData() {
        let emptyData = Data()

        do {
            _ = try AnyValue.deserialize(emptyData)
            XCTFail("Should have thrown empty data error")
        } catch SerializerError.emptyData {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeserializeInvalidCategory() {
        let invalidData = Data([255]) // Invalid category byte

        do {
            _ = try AnyValue.deserialize(invalidData)
            XCTFail("Should have thrown invalid category error")
        } catch SerializerError.invalidCategory(255) {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValueCategoryFromRaw() {
        XCTAssertEqual(ValueCategory.from(0), .null)
        XCTAssertEqual(ValueCategory.from(1), .primitive)
        XCTAssertEqual(ValueCategory.from(2), .list)
        XCTAssertEqual(ValueCategory.from(3), .map)
        XCTAssertEqual(ValueCategory.from(4), .struct)
        XCTAssertEqual(ValueCategory.from(5), .bytes)
        XCTAssertEqual(ValueCategory.from(6), .json)
        XCTAssertNil(ValueCategory.from(255))
    }

    func testPrimitiveI64() async throws {
        let original: Int64 = 42
        let primitiveValue = AnyValue.primitive(original)

        XCTAssertEqual(primitiveValue.category, .primitive)
        XCTAssertEqual(primitiveValue.typeName, "i64")

        // Test type retrieval
        let retrievedValue: Int64 = try await primitiveValue.asType()
        XCTAssertEqual(retrievedValue, original)

        // Test serialization round trip
        let serialized = try await primitiveValue.serialize()
        let deserialized = try AnyValue.deserialize(serialized)
        let resolvedValue: Int64 = try await deserialized.asType()
        XCTAssertEqual(resolvedValue, original)
    }

    func testPrimitiveBool() async throws {
        let original = true
        let primitiveValue = AnyValue.primitive(original)

        XCTAssertEqual(primitiveValue.category, .primitive)
        XCTAssertEqual(primitiveValue.typeName, "bool")

        // Test type retrieval
        let retrievedValue: Bool = try await primitiveValue.asType()
        XCTAssertEqual(retrievedValue, original)

        // Test serialization round trip
        let serialized = try await primitiveValue.serialize()
        let deserialized = try AnyValue.deserialize(serialized)
        let resolvedValue: Bool = try await deserialized.asType()
        XCTAssertEqual(resolvedValue, original)
    }

    func testPrimitiveF64() async throws {
        let original = Double.pi
        let primitiveValue = AnyValue.primitive(original)

        XCTAssertEqual(primitiveValue.category, .primitive)
        XCTAssertEqual(primitiveValue.typeName, "f64")

        // Test type retrieval
        let retrievedValue: Double = try await primitiveValue.asType()
        XCTAssertEqual(retrievedValue, original, accuracy: 0.0001)

        // Test serialization round trip
        let serialized = try await primitiveValue.serialize()
        let deserialized = try AnyValue.deserialize(serialized)
        let resolvedValue: Double = try await deserialized.asType()
        XCTAssertEqual(resolvedValue, original, accuracy: 0.0001)
    }

    func testListSerialization() async throws {
        let original = [
            AnyValue.primitive(1 as Int64),
            AnyValue.primitive("two" as String)
        ]
        let listValue = AnyValue.list(original)

        XCTAssertEqual(listValue.category, .list)
        XCTAssertEqual(listValue.typeName, "list<any>")

        // Test type retrieval
        let retrievedList: [AnyValue] = try await listValue.asType()
        XCTAssertEqual(retrievedList.count, 2)

        let item0: Int64 = try await retrievedList[0].asType()
        XCTAssertEqual(item0, 1)

        let item1: String = try await retrievedList[1].asType()
        XCTAssertEqual(item1, "two")

        // Test serialization round trip
        let serialized = try await listValue.serialize()
        let deserialized = try AnyValue.deserialize(serialized)
        let resolvedList: [AnyValue] = try await deserialized.asType()
        XCTAssertEqual(resolvedList.count, 2)

        let resolvedItem0: Int64 = try await resolvedList[0].asType()
        XCTAssertEqual(resolvedItem0, 1)

        let resolvedItem1: String = try await resolvedList[1].asType()
        XCTAssertEqual(resolvedItem1, "two")
    }

    func testMapSerialization() async throws {
        let original: [String: AnyValue] = [
            "key1": AnyValue.primitive(42 as Int64),
            "key2": AnyValue.primitive("value" as String)
        ]
        let mapValue = AnyValue.map(original)

        XCTAssertEqual(mapValue.category, .map)
        XCTAssertEqual(mapValue.typeName, "map<string,any>")

        // Test type retrieval
        let retrievedMap: [String: AnyValue] = try await mapValue.asType()
        XCTAssertEqual(retrievedMap.count, 2)

        let val1: Int64 = try await retrievedMap["key1"]!.asType()
        XCTAssertEqual(val1, 42)

        let val2: String = try await retrievedMap["key2"]!.asType()
        XCTAssertEqual(val2, "value")

        // Test serialization round trip
        let serialized = try await mapValue.serialize()
        let deserialized = try AnyValue.deserialize(serialized)
        let resolvedMap: [String: AnyValue] = try await deserialized.asType()
        XCTAssertEqual(resolvedMap.count, 2)

        let resolvedVal1: Int64 = try await resolvedMap["key1"]!.asType()
        XCTAssertEqual(resolvedVal1, 42)

        let resolvedVal2: String = try await resolvedMap["key2"]!.asType()
        XCTAssertEqual(resolvedVal2, "value")
    }

    func testJsonSerialization() async throws {
        let original = ["key": "value"]
        let jsonData = try JSONSerialization.data(withJSONObject: original)
        let jsonValue = AnyValue.json(jsonData)

        XCTAssertEqual(jsonValue.category, .json)
        XCTAssertEqual(jsonValue.typeName, "json")

        // Test type retrieval as Data
        let retrievedJsonData: Data = try await jsonValue.asType()
        let retrievedJson = try JSONSerialization.jsonObject(with: retrievedJsonData) as! [String: String]
        XCTAssertEqual(retrievedJson["key"], "value")

        // Test serialization round trip
        let serialized = try await jsonValue.serialize()
        let deserialized = try AnyValue.deserialize(serialized)
        let resolvedJsonData: Data = try await deserialized.asType()
        let resolvedJson = try JSONSerialization.jsonObject(with: resolvedJsonData) as! [String: String]
        XCTAssertEqual(resolvedJson["key"], "value")
    }

    func testNestedStructures() async throws {
        let innerMap: [String: AnyValue] = [
            "num": AnyValue.primitive(42 as Int64),
            "str": AnyValue.primitive("nested" as String)
        ]
        let list = [AnyValue.map(innerMap)]
        let listValue = AnyValue.list(list)

        XCTAssertEqual(listValue.category, .list)

        // Test serialization round trip
        let serialized = try await listValue.serialize()
        let deserialized = try AnyValue.deserialize(serialized)
        let resolvedList: [AnyValue] = try await deserialized.asType()
        XCTAssertEqual(resolvedList.count, 1)

        let innerMapValue = resolvedList[0]
        XCTAssertEqual(innerMapValue.category, .map)

        let resolvedMap: [String: AnyValue] = try await innerMapValue.asType()
        let numVal: Int64 = try await resolvedMap["num"]!.asType()
        XCTAssertEqual(numVal, 42)

        let strVal: String = try await resolvedMap["str"]!.asType()
        XCTAssertEqual(strVal, "nested")
    }

    func testDeserializeBoundsCheck() async {
        // Test malformed data that would cause out-of-bounds access
        let malformedData = Data([1, 0, 2]) // category=1, encrypted=0, type_name_len=2
        // This has 3 bytes total, but claims type_name_len=2
        // Should fail with invalid type name length

        do {
            _ = try AnyValue.deserialize(malformedData)
            XCTFail("Should fail with invalid type name length")
        } catch SerializerError.deserializationFailed(let message) {
            XCTAssertTrue(message.contains("Data too short for type name"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Test with even more malformed data
        let moreMalformed = Data([1, 0, 255]) // type_name_len=255, but only 3 bytes total
        do {
            _ = try AnyValue.deserialize(moreMalformed)
            XCTFail("Should fail with invalid type name length")
        } catch SerializerError.deserializationFailed(let message) {
            XCTAssertTrue(message.contains("Data too short for type name"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Test edge case: exactly at the boundary (should work)
        let edgeCase = Data([1, 0, 1, UInt8(ascii: "a")]) // 4 bytes total, type_name_len=1
        do {
            _ = try AnyValue.deserialize(edgeCase)
            // This will fail for other reasons (invalid type name, missing data), but not bounds check
        } catch {
            // Expected to fail for other reasons, not bounds check
            XCTAssertFalse(error.localizedDescription.contains("bounds"))
        }

        // Test with valid data (should work)
        let testString = "hello"
        let arcValue = AnyValue.primitive(testString)
        let serialized = try! await arcValue.serialize()
        let result = try? AnyValue.deserialize(serialized)
        XCTAssertNotNil(result, "Valid data should deserialize successfully")
    }

    func testSimpleHashMapRoundtrip() async throws {
        let map: [String: String] = [
            "u1": "Alice",
            "u2": "Bob"
        ]
        let mapValue = AnyValue.mapTyped(map)

        // Test serialization without encryption context
        let bytes = try await mapValue.serialize()

        // Test deserialization
        let deserialized = try AnyValue.deserialize(bytes)
        XCTAssertEqual(deserialized.category, .map)

        // Extract typed HashMap
        let typedMap: [String: String] = try await deserialized.asType()

        // Verify the map has the correct number of entries
        XCTAssertEqual(typedMap.count, 2)

        // Verify user1
        let user1 = typedMap["u1"]!
        XCTAssertEqual(user1, "Alice")

        // Verify user2
        let user2 = typedMap["u2"]!
        XCTAssertEqual(user2, "Bob")
    }

    func testSimpleVecRoundtrip() async throws {
        let vec = ["Alice", "Bob"]
        let listValue = AnyValue.listTyped(vec)

        // Test serialization without encryption context
        let bytes = try await listValue.serialize()

        // Test deserialization
        let deserialized = try AnyValue.deserialize(bytes)
        XCTAssertEqual(deserialized.category, .list)

        // Extract typed Vec
        let typedVec: [String] = try await deserialized.asType()

        // Verify the list has the correct number of entries
        XCTAssertEqual(typedVec.count, 2)

        // Verify first element
        let user1 = typedVec[0]
        XCTAssertEqual(user1, "Alice")

        // Verify second element
        let user2 = typedVec[1]
        XCTAssertEqual(user2, "Bob")
    }

    func testMixedContentContainers() async throws {
        // Test containers with mixed content types
        var mixedMap: [String: AnyValue] = [:]

        // Add a primitive
        mixedMap["count"] = AnyValue.primitive(42 as Int64)

        // Add a string
        mixedMap["description"] = AnyValue.primitive("Mixed content test")

        // Add a list of primitives
        mixedMap["scores"] = AnyValue.list([
            AnyValue.primitive(85 as Int64),
            AnyValue.primitive(92 as Int64),
            AnyValue.primitive(78 as Int64)
        ])

        let mapValue = AnyValue.map(mixedMap)

        // Test serialization and deserialization
        let bytes = try await mapValue.serialize()
        let deserialized = try AnyValue.deserialize(bytes)
        XCTAssertEqual(deserialized.category, .map)

        // Extract the map
        let typedMap: [String: AnyValue] = try await deserialized.asType()

        // Verify count
        let count = typedMap["count"]!
        let countValue: Int64 = try await count.asType()
        XCTAssertEqual(countValue, 42)

        // Verify description
        let description = typedMap["description"]!
        let descValue: String = try await description.asType()
        XCTAssertEqual(descValue, "Mixed content test")

        // Verify scores
        let scores = typedMap["scores"]!
        let scoresList: [AnyValue] = try await scores.asType()
        XCTAssertEqual(scoresList.count, 3)

        let score1: Int64 = try await scoresList[0].asType()
        let score2: Int64 = try await scoresList[1].asType()
        let score3: Int64 = try await scoresList[2].asType()

        XCTAssertEqual(score1, 85)
        XCTAssertEqual(score2, 92)
        XCTAssertEqual(score3, 78)
    }

    static let allTests = [
        ("testNullValue", testNullValue),
        ("testPrimitiveString", testPrimitiveString),
        ("testBytesValue", testBytesValue),
        ("testTypeMismatch", testTypeMismatch),
        ("testDeserializeNull", testDeserializeNull),
        ("testDeserializeEmptyData", testDeserializeEmptyData),
        ("testDeserializeInvalidCategory", testDeserializeInvalidCategory),
        ("testValueCategoryFromRaw", testValueCategoryFromRaw),
        ("testPrimitiveI64", testPrimitiveI64),
        ("testPrimitiveBool", testPrimitiveBool),
        ("testPrimitiveF64", testPrimitiveF64),
        ("testListSerialization", testListSerialization),
        ("testMapSerialization", testMapSerialization),
        ("testJsonSerialization", testJsonSerialization),
        ("testNestedStructures", testNestedStructures),
        ("testDeserializeBoundsCheck", testDeserializeBoundsCheck),
        ("testSimpleHashMapRoundtrip", testSimpleHashMapRoundtrip),
        ("testSimpleVecRoundtrip", testSimpleVecRoundtrip),
        ("testMixedContentContainers", testMixedContentContainers),
    ]
}
