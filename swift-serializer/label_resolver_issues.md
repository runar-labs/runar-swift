
Now I have a complete picture! Let me analyze what's actually missing and why:

## 🔍 **ROOT CAUSE ANALYSIS - WHAT'S ACTUALLY MISSING**

### **Current FFI LabelResolver (What We Have):**
```swift
public protocol LabelResolver {
    func resolveLabel(_ label: String) throws -> String  // ❌ Returns just a String
}
```

### **What Field-Level Labels Need (What We're Missing):**

#### **1. Missing Method: `canResolve(_:)`**
**Why We Need It:**
- **Field-level encryption** needs to know if a label can be resolved BEFORE trying to encrypt
- **Partial encryption** - if a label can't be resolved, we skip encrypting that field group
- **Performance** - avoid throwing errors for expected cases (like mobile keystore accessing system-only data)

**Current Problem:**
```swift
// Current approach - throws error if label not found
if let profileId = try? resolver.resolveLabel("system_only") {
    // Encrypt field
} else {
    // Field not encrypted - but we don't know if this was expected or an error
}
```

**Better Approach:**
```swift
// Better approach - check first, then resolve
if resolver.canResolve("system_only") {
    let profileId = try resolver.resolveLabel("system_only")
    // Encrypt field
} else {
    // Field not encrypted - this is expected behavior
}
```

#### **2. Missing Return Type: `LabelKeyInfo` instead of `String`**
**Why We Need It:**
- **Multiple profile keys** - a label might need access to multiple profiles
- **Network vs Profile access** - some labels need network keys, some need profile keys
- **Complex access control** - different keystores have different capabilities

**Current Problem:**
```swift
// Current approach - just returns a profile ID string
let profileId = try resolver.resolveLabel("system")
// But we don't know:
// - Is this network-accessible?
// - Are there multiple profile keys?
// - What type of access is needed?
```

**Better Approach:**
```swift
// Better approach - returns structured access information
let keyInfo = try resolver.resolveLabel("system")
if let networkId = keyInfo.networkId {
    // Use network-based encryption
}
for profileKey in keyInfo.profileIds {
    // Use profile-based encryption
}
```

### **3. Real-World Examples of Why This Matters:**

#### **Example 1: Mobile Keystore Accessing System-Only Data**
```swift
@Encrypted
struct UserProfile: Codable {
    let id: String
    @Runar("user") var privateData: String      // ✅ Mobile can access
    @Runar("system_only") var adminNotes: String // ❌ Mobile cannot access
}

// Current FFI approach:
let profileId = try resolver.resolveLabel("system_only") // ❌ Throws error
// Mobile keystore fails to encrypt adminNotes field

// Enhanced approach:
if resolver.canResolve("system_only") {  // ✅ Returns false
    // Skip encrypting this field - it's expected behavior
} else {
    // Field remains unencrypted, will use defaults on decrypt
}
```

#### **Example 2: Node Keystore with Multiple Access Levels**
```swift
// Current FFI approach:
let profileId = try resolver.resolveLabel("system") // ❌ Returns just "user123"
// We don't know if this needs network keys, profile keys, or both

// Enhanced approach:
let keyInfo = try resolver.resolveLabel("system")
// Returns: LabelKeyInfo(profileIds: ["user123"], networkId: "network456")
// Now we know to encrypt with BOTH profile and network keys
```

### **4. The Real Question: Should We Enhance FFI or Create Adapter?**

**Option A: Enhance FFI LabelResolver (Recommended)**
```swift
// In RunarFFI package
public protocol LabelResolver {
    func canResolve(_ label: String) -> Bool
    func resolveLabel(_ label: String) throws -> LabelKeyInfo
}

public struct LabelKeyInfo {
    public let profileIds: [String]
    public let networkId: String?
}
```

**Pros:**
- ✅ **Single protocol** - no duplication
- ✅ **FFI layer handles complexity** - serializer stays simple
- ✅ **Consistent across all packages** - no adapter needed
- ✅ **Matches Rust implementation** - direct parity

**Cons:**
- ❌ **Breaking change** - existing FFI implementations need updates
- ❌ **FFI package dependency** - need to update FFI first

**Option B: Create Adapter Layer (Alternative)**
```swift
// In serializer package
struct EnhancedLabelResolver {
    private let ffiResolver: RunarFFI.LabelResolver
    func canResolve(_ label: String) -> Bool { ... }
    func resolveLabel(_ label: String) throws -> LabelKeyInfo { ... }
}
```

**Pros:**
- ✅ **No breaking changes** - existing FFI code works
- ✅ **Serializer controls design** - can implement exactly what's needed

**Cons:**
- ❌ **Duplication** - two ways to do the same thing
- ❌ **Complexity** - adapter layer adds indirection
- ❌ **Maintenance** - need to keep adapter in sync with FFI

### **5. My Recommendation: Enhance FFI LabelResolver**

**Why:**
1. **Field-level labels are a core FFI feature** - not just serializer-specific
2. **Rust implementation already has this** - we should match it
3. **Single protocol is cleaner** - no adapter complexity
4. **FFI package is the right place** - it's the foundation layer

**Implementation Plan:**
1. **Update FFI LabelResolver protocol** to include `canResolve` and return `LabelKeyInfo`
2. **Update existing FFI implementations** to support the new protocol
3. **Serializer package uses enhanced FFI protocol** directly
4. **No adapter layer needed** - clean, simple architecture
 