import Foundation

/// A sharded, actor-based concurrent map that provides DashMap-like functionality in Swift 6.
///
/// This implementation uses multiple actors (shards) to provide high concurrency while maintaining
/// thread safety. Each shard serializes access to its portion of the data, but different shards
/// can operate concurrently, similar to Rust's DashMap.
///
/// ## Key Features
/// - **High Concurrency**: Multiple shards allow parallel access to different keys
/// - **Thread Safety**: All operations are actor-isolated and Sendable-compliant
/// - **DashMap Parity**: API designed to match Rust DashMap functionality
/// - **Swift 6 Native**: Uses modern Swift concurrency without @unchecked Sendable
///
/// ## Usage
/// ```swift
/// let map = ShardedConcurrentMap<String, Int>()
/// await map.insert(42, for: "key")
/// let value = await map.get("key") // Returns 42
/// ```
///
/// ## Thread Safety
/// - All operations are `async` and actor-isolated
/// - No `@unchecked Sendable` usage anywhere
/// - Keys must conform to `Hashable & Sendable`
/// - Values must conform to `Sendable`
public final actor ShardedConcurrentMap<Key: Hashable & Sendable, Value: Sendable> {
    // MARK: - Core Properties
    
    /// Number of shards (must be power of 2 for efficient modulo operation)
    private let shardCount: Int
    
    /// Array of shard actors, each managing a portion of the data
    private let shards: [Shard]
    
    /// Mask for efficient modulo operation (shardCount - 1)
    private let shardMask: Int
    
    // MARK: - Shard Actor
    
    /// Individual shard actor that manages a portion of the map data
    private final actor Shard {
        private var storage: [Key: Value] = [:]
        
        func get(_ key: Key) -> Value? {
            return storage[key]
        }
        
        func insert(_ value: Value, for key: Key) -> Value? {
            return storage.updateValue(value, forKey: key)
        }
        
        func remove(_ key: Key) -> Value? {
            return storage.removeValue(forKey: key)
        }
        
        func contains(_ key: Key) -> Bool {
            return storage[key] != nil
        }
        
        func withValue<R: Sendable>(
            for key: Key,
            default makeDefault: @autoclosure @Sendable () -> Value,
            _ body: @Sendable (inout Value) throws -> R
        ) rethrows -> R {
            if storage[key] == nil {
                storage[key] = makeDefault()
            }
            return try body(&storage[key]!)
        }
        
        func count() -> Int {
            return storage.count
        }
        
        func keys() -> [Key] {
            return Array(storage.keys)
        }
        
        func values() -> [Value] {
            return Array(storage.values)
        }
        
        func forEach(_ body: (Key, Value) -> Void) {
            for (key, value) in storage {
                body(key, value)
            }
        }
        
        func clear() {
            storage.removeAll()
        }
    }
    
    // MARK: - Initialization
    
    /// Create a new ShardedConcurrentMap with the specified number of shards.
    ///
    /// - Parameter shardCount: Number of shards (must be power of 2, defaults to 32)
    /// - Precondition: `shardCount` must be a power of 2 and > 0
    public init(shardCount: Int = 32) {
        precondition(shardCount > 0 && (shardCount & (shardCount - 1)) == 0, 
                    "shardCount must be a power of 2 and > 0")
        
        self.shardCount = shardCount
        self.shardMask = shardCount - 1
        self.shards = (0..<shardCount).map { _ in Shard() }
    }
    
    // MARK: - Core Operations
    
    /// Get the value for a key.
    ///
    /// - Parameter key: The key to look up
    /// - Returns: The value if it exists, `nil` otherwise
    public func get(_ key: Key) async -> Value? {
        let shard = getShard(for: key)
        return await shard.get(key)
    }
    
    /// Insert a value for a key, returning the previous value if it existed.
    ///
    /// - Parameters:
    ///   - value: The value to insert
    ///   - key: The key to associate with the value
    /// - Returns: The previous value if it existed, `nil` otherwise
    public func insert(_ value: Value, for key: Key) async -> Value? {
        let shard = getShard(for: key)
        return await shard.insert(value, for: key)
    }
    
    /// Remove a key and return its value if it existed.
    ///
    /// - Parameter key: The key to remove
    /// - Returns: The value that was removed if it existed, `nil` otherwise
    public func remove(_ key: Key) async -> Value? {
        let shard = getShard(for: key)
        return await shard.remove(key)
    }
    
    /// Check if a key exists in the map.
    ///
    /// - Parameter key: The key to check
    /// - Returns: `true` if the key exists, `false` otherwise
    public func contains(_ key: Key) async -> Bool {
        let shard = getShard(for: key)
        return await shard.contains(key)
    }
    
    /// Atomically get or initialize a value and then mutate it.
    ///
    /// This is equivalent to DashMap's `entry(key).or_default()` pattern.
    /// The operation is atomic - no other operation on the same key can interleave.
    ///
    /// - Parameters:
    ///   - key: The key to get or initialize
    ///   - makeDefault: Closure to create a default value if the key doesn't exist
    ///   - body: Closure to mutate the value (inout parameter)
    /// - Returns: The result of the body closure
    /// - Throws: Any error thrown by the body closure
    public func withValue<R: Sendable>(
        for key: Key,
        default makeDefault: @autoclosure @Sendable () -> Value,
        _ body: @Sendable (inout Value) throws -> R
    ) async rethrows -> R {
        let shard = getShard(for: key)
        return try await shard.withValue(for: key, default: makeDefault(), body)
    }
    
    // MARK: - Introspection Operations
    
    /// Get the total number of key-value pairs across all shards.
    ///
    /// - Returns: The total count
    public func count() async -> Int {
        var total = 0
        for shard in shards {
            total += await shard.count()
        }
        return total
    }
    
    /// Get all keys across all shards.
    ///
    /// - Returns: Array of all keys
    public func keys() async -> [Key] {
        var allKeys: [Key] = []
        for shard in shards {
            let shardKeys = await shard.keys()
            allKeys.append(contentsOf: shardKeys)
        }
        return allKeys
    }
    
    /// Get all values across all shards.
    ///
    /// - Returns: Array of all values
    public func values() async -> [Value] {
        var allValues: [Value] = []
        for shard in shards {
            let shardValues = await shard.values()
            allValues.append(contentsOf: shardValues)
        }
        return allValues
    }
    
    /// Execute a closure for each key-value pair across all shards.
    ///
    /// - Parameter body: Closure to execute for each key-value pair
    public func forEach(_ body: @Sendable (Key, Value) -> Void) async {
        for shard in shards {
            await shard.forEach(body)
        }
    }
    
    /// Remove all key-value pairs from the map.
    public func clear() async {
        for shard in shards {
            await shard.clear()
        }
    }
    
    // MARK: - Private Helpers
    
    /// Get the appropriate shard for a given key.
    ///
    /// - Parameter key: The key to find a shard for
    /// - Returns: The shard actor for this key
    private func getShard(for key: Key) -> Shard {
        let hash = key.hashValue
        let shardIndex = abs(hash) & shardMask
        return shards[shardIndex]
    }
}

// MARK: - CustomStringConvertible

extension ShardedConcurrentMap: CustomStringConvertible {
    public nonisolated var description: String {
        return "ShardedConcurrentMap(\(shardCount) shards)"
    }
}

// MARK: - CustomDebugStringConvertible

extension ShardedConcurrentMap: CustomDebugStringConvertible {
    public nonisolated var debugDescription: String {
        return "ShardedConcurrentMap<\(Key.self), \(Value.self)>(shards: \(shardCount))"
    }
}
