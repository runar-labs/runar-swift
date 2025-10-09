## TopicPath API Mismatch Issues Between Swift and Rust

Based on my analysis of both codebases, here are the **critical API mismatches** that need to be fixed:

### 1. **Primary Constructor API Mismatch**

**Rust API:**
```rust
TopicPath::new(&service_path, &network_id) -> Result<Self, String>
```

**Swift API (WRONG):**
```swift
TopicPath(networkId: String, segments: [String]) throws
```

**Issue:** Swift takes `segments` array, but Rust takes a single `service_path` string. This is the root cause of the current problem.

### 2. **String Concatenation Anti-Pattern**

**Current Swift Code (WRONG):**
```swift
let fullPath = "\(nodeInfo.networkIds.first ?? "default"):\(servicePath)"
let topicPath = try TopicPath.parse(fullPath)
```

**Rust Pattern (CORRECT):**
```rust
TopicPath::new(&service_metadata.service_path, &service_metadata.network_id)
```

**Issue:** Swift is concatenating strings instead of using the proper constructor.

### 3. **Missing Equivalent Methods**

**Rust has:**
- `TopicPath::new(path, network_id)` - Primary constructor
- `TopicPath::new_service(network_id, service_name)` - Service-only constructor  
- `TopicPath::from_full_path(path)` - Parse full path string

**Swift has:**
- `TopicPath(networkId:segments:)` - Wrong constructor -  needs to be changed to alieng with RUST API. same behaviour  same argfumetn order and types.
- `TopicPath.parse(fullPath)` - Equivalent to `from_full_path` -  neds to be renamed to match Rust name.
- `TopicPath.newService(networkId:serviceName:)` - Equivalent to `new_service`

**Missing:** Swift needs `TopicPath.new(path:networkId:)` equivalent to Rust's `TopicPath::new()`

### 4. **Incorrect Usage Patterns**

**Current Swift (WRONG):**
```swift
// Creating segments manually
let topicPath = try TopicPath(networkId: networkId, segments: servicePath.split(separator: "/").map(String.init))
```

**Should be (like Rust):**
```swift
// Direct path string like Rust
let topicPath = try TopicPath.new(path: servicePath, networkId: networkId)
```

### 5. **Service Path vs Action Path Confusion**

**Rust Pattern:**
```rust
// For service: TopicPath::new("math1", "test-network")
// For action: TopicPath::new("math1/add", "test-network")  
```

**Swift Current (WRONG):**
```swift
// Creating action path incorrectly
let topicPath = try TopicPath(networkId: service.networkId, segments: servicePath.split(separator: "/").map(String.init))
```

### 6. **Network ID Handling Inconsistency**

**Rust:** Network ID is always the second parameter
**Swift:** Network ID is the first parameter in constructor, but `parse()` expects `networkId:path` format

## Required Fixes

1. **Add `TopicPath.new(path:networkId:)` method** to match Rust API exactly
2. **Replace all string concatenation** with proper constructor calls
3. **Update all usage sites** to use the correct API pattern
4. **Ensure network ID handling** matches Rust exactly
5. **Fix service vs action path creation** to match Rust patterns

The core issue is that Swift is trying to manually construct segments when Rust just takes a path string and parses it internally. This mismatch is causing the remote handler registration to fail because the TopicPath objects don't match between registration and lookup.


UPDATE ALL TESTS TO USE TEH PROPER API>.

NO BACKWARD COMPAT>> FULL REFACTORY>> UDPET ALL AFFECTED CODE in the common pavkage.. DO NOT CHANGE ANY OTHER PACAKGE