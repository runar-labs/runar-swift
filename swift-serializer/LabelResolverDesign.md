# Swift Label Resolver — Rust Parity Design

## Goal

Design and specify a Swift-only Label Resolver that mirrors the Rust `runar-serializer` behavior exactly. The resolver maps human-readable labels (e.g., "system", "user") to concrete recipients expressed as actual public key bytes required by the CommonKeyManager envelope encryption APIs. No CommonKeyManager label APIs exist; all resolution happens in Swift. The CommonKeyManager protocol is implemented by both NodeKeyManager and MobileKeyManager.

## Rust Parity Summary

Relevant Rust components (conceptual mapping):
- LabelKeyInfo { profile_public_keys: Vec<Vec<u8>>, network_public_key: Option<Vec<u8>> }
- LabelResolverConfig { label_mappings: HashMap<String, LabelValue> }
- LabelValue { network_public_key: Option<Vec<u8>>, user_key_spec: Option<LabelKeyword> }
- LabelKeyword { CurrentUser, Custom(String) }
- LabelResolver::create_context_label_resolver(system_config, user_profile_keys) -> LabelResolver
- Validation: Config must be explicit; a label must specify at least one of network or user spec (or both). No implicit defaults.
- Caching: Resolver instances may be cached keyed by the profile keys set for performance.

The Swift design matches these features and behavior with deterministic semantics and no fallbacks.

## Swift Types and APIs

### Public Data Structures

```swift
public struct LabelKeyInfo: Sendable, Equatable {
    public let profilePublicKeys: [Data]
    public let networkPublicKey: Data?
}

public enum LabelKeyword: Equatable, Sendable {
    case currentUser
    case custom(String)
}

public struct LabelValue: Sendable, Equatable {
    public let networkPublicKey: Data?
    public let userKeySpec: LabelKeyword?
}

public struct LabelResolverConfig: Sendable, Equatable {
    public let labelMappings: [String: LabelValue]
}
```

- All keys are raw public key bytes (Data). No IDs, no lookups by name at CommonKeyManager.
- Labels are case-sensitive and must match exactly.

### Errors

```swift
public enum LabelResolverError: Error, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case labelUnavailable(String)
    case keyLengthInvalid(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(msg): return "Invalid label resolver configuration: \(msg)"
        case let .labelUnavailable(label): return "Label unavailable: \(label)"
        case let .keyLengthInvalid(msg): return "Invalid key length: \(msg)"
        }
    }
}
```

### Resolver

Immutable, value-type resolver with constant-time lookups. Thread-safe by design with no internal mutation.

```swift
public struct LabelResolver: Sendable, Equatable {
    private let mapping: [String: LabelKeyInfo]

    public init(mapping: [String: LabelKeyInfo]) {
        self.mapping = mapping
    }

    public func canResolve(_ label: String) -> Bool {
        mapping[label] != nil
    }

    public func resolveLabelInfo(_ label: String) throws -> LabelKeyInfo {
        guard let info = mapping[label] else { throw LabelResolverError.labelUnavailable(label) }
        return info
    }

    public func availableLabels() -> [String] {
        Array(mapping.keys).sorted()
    }
}
```

// (Factory moved to Future (Node-only) section below)

### Key Validation

Strict validation prevents misconfiguration at runtime and aligns with “no fallbacks”.

```swift
private func validate(systemConfig: LabelResolverConfig) throws {
    if systemConfig.labelMappings.isEmpty {
        throw LabelResolverError.invalidConfiguration("labelMappings must not be empty")
    }
    // All labels must be unique and non-empty
    for (label, value) in systemConfig.labelMappings {
        if label.isEmpty { throw LabelResolverError.invalidConfiguration("Empty label name") }
        let hasNetwork = value.networkPublicKey != nil
        let hasUserSpec = value.userKeySpec != nil
        if !hasNetwork && !hasUserSpec {
            throw LabelResolverError.invalidConfiguration("Label '\(label)' must specify either networkPublicKey or userKeySpec (or both)")
        }
        if let net = value.networkPublicKey, net.isEmpty {
            throw LabelResolverError.invalidConfiguration("Label '\(label)' has empty networkPublicKey — use nil for profile-only labels")
        }
    }
}

private func validatePublicKeys(networkKey: Data?, profileKeys: [Data], label: String) throws {
    // Example constraints (adjust to actual crypto suite):
    // - Ed25519 public keys: 32 bytes
    // - X25519 public keys: 32 bytes
    // If key types are mixed, validation should be aware of the expected algorithm per system policy.
    func isValidLength(_ data: Data?) -> Bool { data == nil || data!.count == 32 }

    if !isValidLength(networkKey) {
        throw LabelResolverError.keyLengthInvalid("networkPublicKey for label \(label) must be 32 bytes")
    }
    for (idx, key) in profileKeys.enumerated() {
        if key.count != 32 {
            throw LabelResolverError.keyLengthInvalid("profilePublicKeys[\(idx)] for label \(label) must be 32 bytes")
        }
    }
}
```

Notes:
- Adjust lengths and algorithm checks to the actual key types enforced by the CommonKeyManager keystore. The validation logic should be centralized and reused across call sites.

// (Caching moved to Future (Node-only) section below)

## Deterministic Behavior and No Fallbacks

- If a label is not configured or cannot be resolved under the current context, `canResolve` is false and `resolveLabelInfo` throws. Encryption paths must treat this as expected for optional label groups (e.g., `system_only`) and omit the group.
- There are no defaults or silent recoveries; all mappings are explicit.

## Integration with Encryption

- `encryptLabelGroup` consumes `LabelResolver` to obtain `LabelKeyInfo` with pre-resolved recipients, then calls `CommonKeyManager.encryptWithEnvelope(data:networkPublicKey:profilePublicKeys:)` (exact API from CommonKeyManager protocol).
- Missing label → omit group (store `nil` envelope) by contract in the higher-level orchestration.

Example usage:

```swift
let config = LabelResolverConfig(labelMappings: [
    "system": LabelValue(networkPublicKey: systemNetPK, userKeySpec: .currentUser),
    "user":   LabelValue(networkPublicKey: userNetPK,   userKeySpec: .currentUser),
    "search": LabelValue(networkPublicKey: searchNetPK, userKeySpec: nil),
])

let resolver = try LabelResolverFactory.createContextResolver(
    systemConfig: config,
    userProfilePublicKeys: [currentUserProfilePK]
)

if resolver.canResolve("system") {
    let info = try resolver.resolveLabelInfo("system")
    // info.networkPublicKey, info.profilePublicKeys → feed to EnvelopeCrypto
}
```

## Validation Rules (Mirror Rust)

- System config must contain at least one mapping.
- Each label must specify at least one of `networkPublicKey` or `userKeySpec` (or both). Network-only and profile-only labels are valid. A label with neither is invalid.
- `userKeySpec.custom(String)` is allowed only if the calling layer has pre-resolved the custom selector to concrete public keys before factory invocation (i.e., system-specific policy). The provided design throws otherwise to avoid implicit fallbacks.
- Key byte lengths are validated according to the crypto suite (typically 32 bytes for x25519/ed25519). This must be kept in sync with the CommonKeyManager.

## Thread-Safety and Performance

- `LabelResolver` is immutable; lookups are O(1) and thread-safe.
- A cache (optional) can eliminate repeated resolver construction for identical contexts.
- No actors are required for the resolver itself, avoiding async overhead in hot encryption paths.

## Testing Strategy

- Construct resolvers using real public key bytes from `swift-test-utils` fixtures.
- Use real NodeKeyManager or MobileKeyManager instances (both implement CommonKeyManager) for encryption/decryption testing.
- Verify:
  - Validation rejects incomplete or malformed configs (missing network keys, empty labels, wrong key lengths).
  - `currentUser` yields exactly the passed user profile keys.
  - `availableLabels()` returns a sorted set matching config.
  - `canResolve`/`resolveLabelInfo` behave deterministically.
  - End-to-end: label-group encryption produces envelopes with expected recipients and decrypts correctly under node vs mobile keystores (partial access semantics verified at orchestrator layer).

Implementation note for tests:
- For serializer tests, construct `LabelResolver` manually (no Factory, no context, no cache). This mirrors Rust tests and avoids introducing context concepts before Node work.

## Future (Node-only) - DO NOT IMPLEMENT THIS NOW.. just for future reference.

The following sections are for future reference only and MUST NOT be implemented now. They will be introduced when building the Swift Node, where request/user contexts exist.

### Factory (Context-Aware Construction)

Construct a resolver for a specific request context (e.g., current user’s profile public keys).

```swift
public enum LabelResolverFactory {
    public static func createContextResolver(
        systemConfig: LabelResolverConfig,
        userProfilePublicKeys: [Data]
    ) throws -> LabelResolver {
        try validate(systemConfig: systemConfig)
        var out: [String: LabelKeyInfo] = [:]
        out.reserveCapacity(systemConfig.labelMappings.count)
        for (label, value) in systemConfig.labelMappings {
            let networkKey = value.networkPublicKey
            let profileKeys: [Data]
            if let spec = value.userKeySpec {
                switch spec {
                case .currentUser:
                    profileKeys = userProfilePublicKeys
                case let .custom(name):
                    throw LabelResolverError.invalidConfiguration("Custom userKeySpec '" + name + "' requires explicit pre-resolution before factory call")
                }
            } else {
                profileKeys = []
            }
            try validatePublicKeys(networkKey: networkKey, profileKeys: profileKeys, label: label)
            out[label] = LabelKeyInfo(profilePublicKeys: profileKeys, networkPublicKey: networkKey)
        }
        return LabelResolver(mapping: out)
    }
}
```

### Caching

A cache can reduce allocations for identical contexts. The cache key should be a stable fingerprint of the user profile public keys (order-insensitive) and a system config version.

```swift
public final class LabelResolverCache: @unchecked Sendable {
    private struct CacheKey: Hashable {
        let systemConfigVersion: String
        let profileKeysDigest: Data
    }
    private let cache = NSCache<WrappedKey, WrappedValue>()
    public init(maxEntries: Int = 1024) { cache.countLimit = maxEntries }
    public func getOrCreate(
        systemConfig: LabelResolverConfig,
        systemConfigVersion: String,
        userProfilePublicKeys: [Data]
    ) throws -> LabelResolver {
        let digest = digestKeys(userProfilePublicKeys)
        let key = CacheKey(systemConfigVersion: systemConfigVersion, profileKeysDigest: digest)
        let wrappedKey = WrappedKey(key)
        if let existing = cache.object(forKey: wrappedKey)?.resolver { return existing }
        let created = try LabelResolverFactory.createContextResolver(systemConfig: systemConfig, userProfilePublicKeys: userProfilePublicKeys)
        cache.setObject(WrappedValue(created), forKey: wrappedKey)
        return created
    }
    private func digestKeys(_ keys: [Data]) -> Data {
        let sorted = keys.sorted { $0.lexicographicallyPrecedes($1) }
        return Data(sorted.flatMap { $0 }) // Replace with CryptoKit SHA256 in production
    }
    private final class WrappedKey: NSObject { let key: CacheKey; init(_ key: CacheKey) { self.key = key } ; override var hash: Int { key.hashValue } ; override func isEqual(_ object: Any?) -> Bool { (object as? WrappedKey)?.key == key } }
    private final class WrappedValue: NSObject { let resolver: LabelResolver; init(_ resolver: LabelResolver) { self.resolver = resolver } }
}
```

## Acceptance Criteria

- All API surfaces compile and are Sendable where applicable.
- Behavior matches Rust semantics: explicit configuration, context-bound key resolution, no fallbacks, deterministic outcomes.
- Validation errors are precise and fail early.
- Performance is suitable for hot paths without actor overhead.

## Extensibility Notes

- If future policies allow labels without network recipients, relax validation per label (documented and enforced).
- If additional selector keywords are needed, extend `LabelKeyword` and update factory policy accordingly (still no implicit defaults).
- If multi-tenant or multi-network contexts are used, prefix/scope labels or add namespacing in `LabelResolverConfig`.
