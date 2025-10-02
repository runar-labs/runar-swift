@testable import SwiftCommon
import XCTest

/// Comprehensive test suite for ShardedConcurrentMap
///
/// Tests all functionality to ensure DashMap parity and thread safety.
final class ShardedConcurrentMapTests: XCTestCase {
    // MARK: - Basic Operations Tests

    func testBasicInsertAndGet() async {
        let map = ShardedConcurrentMap<String, Int>()

        // Test insert and get
        let previousValue = await map.insert(42, for: "test")
        XCTAssertNil(previousValue, "First insert should return nil")

        let retrievedValue = await map.get("test")
        XCTAssertEqual(retrievedValue, 42, "Retrieved value should match inserted value")
    }

    func testInsertOverwrite() async {
        let map = ShardedConcurrentMap<String, Int>()

        // Insert first value
        let firstPrevious = await map.insert(42, for: "test")
        XCTAssertNil(firstPrevious, "First insert should return nil")

        // Overwrite with new value
        let secondPrevious = await map.insert(100, for: "test")
        XCTAssertEqual(secondPrevious, 42, "Second insert should return previous value")

        // Verify new value
        let currentValue = await map.get("test")
        XCTAssertEqual(currentValue, 100, "Current value should be the new value")
    }

    func testRemove() async {
        let map = ShardedConcurrentMap<String, Int>()

        // Insert a value
        _ = await map.insert(42, for: "test")

        // Remove it
        let removedValue = await map.remove("test")
        XCTAssertEqual(removedValue, 42, "Remove should return the removed value")

        // Verify it's gone
        let retrievedValue = await map.get("test")
        XCTAssertNil(retrievedValue, "Value should be nil after removal")
    }

    func testRemoveNonExistent() async {
        let map = ShardedConcurrentMap<String, Int>()

        let removedValue = await map.remove("nonexistent")
        XCTAssertNil(removedValue, "Removing non-existent key should return nil")
    }

    func testContains() async {
        let map = ShardedConcurrentMap<String, Int>()

        // Test non-existent key
        let containsBefore = await map.contains("test")
        XCTAssertFalse(containsBefore, "Non-existent key should not be contained")

        // Insert key
        _ = await map.insert(42, for: "test")

        // Test existing key
        let containsAfter = await map.contains("test")
        XCTAssertTrue(containsAfter, "Existing key should be contained")
    }

    // MARK: - WithValue Tests (DashMap entry().or_default() equivalent)

    func testWithValueNewKey() async {
        let map = ShardedConcurrentMap<String, [Int]>()

        let result = await map.withValue(for: "test", default: []) { values in
            values.append(42)
            values.append(100)
            return values.count
        }

        XCTAssertEqual(result, 2, "Should have added 2 values")

        let retrievedValues = await map.get("test")
        XCTAssertEqual(retrievedValues, [42, 100], "Retrieved values should match")
    }

    func testWithValueExistingKey() async {
        let map = ShardedConcurrentMap<String, [Int]>()

        // Pre-populate
        _ = await map.insert([1, 2, 3], for: "test")

        let result = await map.withValue(for: "test", default: []) { values in
            values.append(4)
            values.append(5)
            return values.count
        }

        XCTAssertEqual(result, 5, "Should have 5 values total")

        let retrievedValues = await map.get("test")
        XCTAssertEqual(retrievedValues, [1, 2, 3, 4, 5], "Retrieved values should include both old and new")
    }

    func testWithValueThrowing() async {
        let map = ShardedConcurrentMap<String, Int>()

        do {
            try await map.withValue(for: "test", default: 0) { _ in
                throw TestError.someError
            }
            XCTFail("Should have thrown an error")
        } catch TestError.someError {
            // Expected
        } catch {
            XCTFail("Should have thrown TestError.someError")
        }

        // Value should be inserted even if body throws (DashMap behavior)
        let value = await map.get("test")
        XCTAssertEqual(value, 0, "Value should exist after throwing error (DashMap behavior)")
    }

    // MARK: - Introspection Tests

    func testCount() async {
        let map = ShardedConcurrentMap<String, Int>()

        // Empty map
        let emptyCount = await map.count()
        XCTAssertEqual(emptyCount, 0, "Empty map should have count 0")

        // Add some values
        _ = await map.insert(1, for: "key1")
        _ = await map.insert(2, for: "key2")
        _ = await map.insert(3, for: "key3")

        let count = await map.count()
        XCTAssertEqual(count, 3, "Map should have count 3")
    }

    func testKeys() async {
        let map = ShardedConcurrentMap<String, Int>()

        // Empty map
        let emptyKeys = await map.keys()
        XCTAssertTrue(emptyKeys.isEmpty, "Empty map should have no keys")

        // Add some values
        _ = await map.insert(1, for: "key1")
        _ = await map.insert(2, for: "key2")
        _ = await map.insert(3, for: "key3")

        let keys = await map.keys()
        XCTAssertEqual(Set(keys), Set(["key1", "key2", "key3"]), "Keys should match inserted keys")
    }

    func testValues() async {
        let map = ShardedConcurrentMap<String, Int>()

        // Empty map
        let emptyValues = await map.values()
        XCTAssertTrue(emptyValues.isEmpty, "Empty map should have no values")

        // Add some values
        _ = await map.insert(1, for: "key1")
        _ = await map.insert(2, for: "key2")
        _ = await map.insert(3, for: "key3")

        let values = await map.values()
        XCTAssertEqual(Set(values), Set([1, 2, 3]), "Values should match inserted values")
    }

    func testForEach() async {
        let map = ShardedConcurrentMap<String, Int>()

        // Add some values
        _ = await map.insert(1, for: "key1")
        _ = await map.insert(2, for: "key2")
        _ = await map.insert(3, for: "key3")

        // Test that forEach executes without crashing
        // We can't easily test the exact iteration order due to Sendable constraints
        // but we can verify it doesn't crash and processes all items
        await map.forEach { key, value in
            // Just verify the key and value are reasonable
            XCTAssertTrue(key.count > 0, "Key should not be empty")
            XCTAssertTrue(value > 0, "Value should be positive")
        }
    }

    func testClear() async {
        let map = ShardedConcurrentMap<String, Int>()

        // Add some values
        _ = await map.insert(1, for: "key1")
        _ = await map.insert(2, for: "key2")
        _ = await map.insert(3, for: "key3")

        // Verify they exist
        let countBefore = await map.count()
        XCTAssertEqual(countBefore, 3, "Should have 3 items before clear")

        // Clear
        await map.clear()

        // Verify they're gone
        let countAfter = await map.count()
        XCTAssertEqual(countAfter, 0, "Should have 0 items after clear")

        let keys = await map.keys()
        XCTAssertTrue(keys.isEmpty, "Should have no keys after clear")
    }

    // MARK: - Concurrency Tests

    func testConcurrentInserts() async {
        let map = ShardedConcurrentMap<Int, String>()
        let keyCount = 1000

        // Create multiple concurrent tasks inserting different keys
        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< keyCount {
                group.addTask {
                    _ = await map.insert("value\(index)", for: index)
                }
            }
        }

        // Verify all keys were inserted
        let count = await map.count()
        XCTAssertEqual(count, keyCount, "Should have inserted all keys")

        // Verify some specific values
        for index in 0 ..< min(10, keyCount) {
            let value = await map.get(index)
            XCTAssertEqual(value, "value\(index)", "Value should match for key \(index)")
        }
    }

    func testConcurrentReadsAndWrites() async {
        let map = ShardedConcurrentMap<String, Int>()
        let keyCount = 100

        // Start with some initial data
        for index in 0 ..< keyCount {
            _ = await map.insert(index, for: "key\(index)")
        }

        // Concurrent reads and writes
        await withTaskGroup(of: Void.self) { group in
            // Reader tasks - just verify values exist and are reasonable
            for _ in 0 ..< 10 {
                group.addTask {
                    for index in 0 ..< keyCount {
                        let value = await map.get("key\(index)")
                        XCTAssertNotNil(value, "Value should exist for key\(index)")
                        XCTAssertTrue(value! >= 0, "Value should be non-negative")
                    }
                }
            }

            // Writer tasks - update values
            for _ in 0 ..< 5 {
                group.addTask {
                    for index in 0 ..< keyCount {
                        _ = await map.insert(index * 2, for: "key\(index)")
                    }
                }
            }
        }

        // Verify final state
        let count = await map.count()
        XCTAssertEqual(count, keyCount, "Should still have all keys")
    }

    func testConcurrentWithValue() async {
        let map = ShardedConcurrentMap<String, [Int]>()
        let keyCount = 100

        // Concurrent withValue operations
        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< keyCount {
                group.addTask {
                    _ = await map.withValue(for: "key\(index)", default: []) { values in
                        values.append(index)
                        values.append(index * 2)
                        return values.count
                    }
                }
            }
        }

        // Verify results
        let count = await map.count()
        XCTAssertEqual(count, keyCount, "Should have all keys")

        // Check some specific values
        for index in 0 ..< min(10, keyCount) {
            let values = await map.get("key\(index)")
            XCTAssertEqual(values, [index, index * 2], "Values should match for key \(index)")
        }
    }

    // MARK: - Sharding Tests

    func testShardingDistribution() async {
        let map = ShardedConcurrentMap<Int, String>(shardCount: 8)
        let keyCount = 1000

        // Insert many keys
        for index in 0 ..< keyCount {
            _ = await map.insert("value\(index)", for: index)
        }

        // Verify all keys are accessible
        let count = await map.count()
        XCTAssertEqual(count, keyCount, "Should have all keys")

        // Verify some specific keys
        for index in stride(from: 0, to: keyCount, by: 100) {
            let value = await map.get(index)
            XCTAssertEqual(value, "value\(index)", "Value should match for key \(index)")
        }
    }

    func testCustomShardCount() async {
        let map = ShardedConcurrentMap<String, Int>(shardCount: 4)

        // Test that it works with custom shard count
        _ = await map.insert(42, for: "test")
        let value = await map.get("test")
        XCTAssertEqual(value, 42, "Should work with custom shard count")
    }

    // MARK: - Edge Cases

    func testEmptyMapOperations() async {
        let map = ShardedConcurrentMap<String, Int>()

        let count = await map.count()
        XCTAssertEqual(count, 0, "Empty map should have count 0")

        let keys = await map.keys()
        XCTAssertTrue(keys.isEmpty, "Empty map should have no keys")

        let values = await map.values()
        XCTAssertTrue(values.isEmpty, "Empty map should have no values")

        // Test forEach on empty map
        await map.forEach { _, _ in
            XCTFail("forEach should not be called on empty map")
        }
    }

    func testNilValues() async {
        let map = ShardedConcurrentMap<String, Int?>()

        _ = await map.insert(nil, for: "nilKey")
        let value = await map.get("nilKey")
        XCTAssertEqual(value, .some(nil), "Should be able to store and retrieve nil values")

        let contains = await map.contains("nilKey")
        XCTAssertTrue(contains, "Should contain key with nil value")
    }

    // MARK: - Performance Tests

    func testLargeDataset() async {
        let map = ShardedConcurrentMap<Int, String>()
        let keyCount = 10000

        // Measure insertion time
        let startTime = CFAbsoluteTimeGetCurrent()

        for index in 0 ..< keyCount {
            _ = await map.insert("value\(index)", for: index)
        }

        let insertionTime = CFAbsoluteTimeGetCurrent() - startTime
        print("Inserted \(keyCount) items in \(insertionTime) seconds")

        // Verify count
        let count = await map.count()
        XCTAssertEqual(count, keyCount, "Should have all items")

        // Verify some random samples
        for _ in 0 ..< 100 {
            let randomKey = Int.random(in: 0 ..< keyCount)
            let value = await map.get(randomKey)
            XCTAssertEqual(value, "value\(randomKey)", "Random sample should match")
        }
    }
}

// MARK: - Test Helpers

private enum TestError: Error {
    case someError
}
