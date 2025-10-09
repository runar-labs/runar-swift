These comments are weird:
// Ensure TestProfile is registered before any serialization
logger.trace("Registering TestProfile with serialization registry")
_ = try await profile.encryptWithKeystore(mobileKs, resolver)
logger.info("TestProfile registration complete")

What does this mean ? that the type is being added to the registry when we call encryptWithKeystore??

the registry shuold not be done when we call encryptWithKeystore.
the tyope shuold be added add to the registry  by the macro. or when the sytem starts. 

beucause we can have the sceanario of a code that never encrpts a types BUT needs to decrypt it. and it still needs the entry in the registry. the way rust works is it uses CTOR. so when the app/code runst it will registry all the types that have macro. will add them to the registry at app/code start. do we have something similar in swift 6 that we can use ? a handler that is called when app/code starts? so we can register all the types anotate by the macro ?  

BEFORE ANY CHAGNES ON THIS we need proper analisys an design.. we need to first explore the options to choose the best option in swift before making any changes. so DO a prpe research and get back to me with optoins.


ALSO WHY IS THIS BEING DONE THIS WAY ? Maybe a similar issue here ?

 // Create serialization context - resolve network_public_key from resolver
logger.trace("Creating serialization context")
_ = try resolver.resolveLabelInfo("system")
        
why does resolver.resolveLabelInfo("system") needs to be called here?  nothign is done with the result ?  I see this happneing in many tests ? why ?

## SOLUTION: Synchronous Registration at Startup

### Problem Analysis
1. **Registry Registration Timing**: Currently using `_ = try await profile.encryptWithKeystore(mobileKs, resolver)` just to register types - this is wrong
2. **Unnecessary Resolver Call**: `_ = try resolver.resolveLabelInfo("system")` is called but result is unused
3. **Async Registration**: `_ensureRegistered()` is async because `SerializationRegistry` is an actor, but registration only happens at startup

### Root Cause
- `SerializationRegistry` is an actor requiring async calls
- Registration happens at runtime instead of startup
- Rust uses `#[ctor::ctor]` for automatic startup registration
- Swift needs equivalent startup mechanism

### Solution: Synchronous Registration Methods
Replace async registration with synchronous methods since registration only happens at initialization:

```swift
// In SerializationRegistry.swift - add synchronous registration methods
public nonisolated func registerEncryptorSync<T: Encodable & Sendable>(
    for _: T.Type,
    wireName: String? = nil,
    targetEncryptedWireName: String? = nil,
    encryptor: @escaping @Sendable (T, CommonKeyManager, LabelResolver) async throws -> Data
) {
    // Use thread-safe synchronization for startup registration
}

public nonisolated func registerDecryptorSync<T: Decodable & Sendable>(
    for _: T.Type,
    wireName: String? = nil,
    decryptor: @escaping @Sendable (Data, CommonKeyManager) async throws -> T
) {
    // Use thread-safe synchronization for startup registration
}

public nonisolated func registerDecoderSync(
    for wireName: String,
    decoder: @escaping @Sendable (Data) throws -> (any Decodable & Sendable)
) {
    // Use thread-safe synchronization for startup registration
}

public nonisolated func registerWireNameSync<T>(for _: T.Type, wireName: String) {
    // Use thread-safe synchronization for startup registration
}
```

```swift
// In EncryptedMacro.swift - use static initialization like Rust
private static let _registration: Void = {
    SerializationRegistry.shared.registerEncryptorSync(for: Self.self, wireName: "\(wireName)", targetEncryptedWireName: "Encrypted_\(wireName)") { value, keystore, resolver in
        let enc = try await value.encryptWithKeystore(keystore, resolver)
        let encoder = SwiftCBOR.CodableCBOREncoder()
        return try encoder.encode(enc)
    }
    SerializationRegistry.shared.registerDecryptorSync(for: Self.self, wireName: "Encrypted_\(wireName)") { data, keystore in
        let encrypted = try SwiftCBOR.CodableCBORDecoder().decode(Encrypted\(structName).self, from: data)
        return try await encrypted.decryptWithKeystore(keystore)
    }
    SerializationRegistry.shared.registerWireNameSync(for: Self.self, wireName: "\(wireName)")
    SerializationRegistry.shared.registerDecoderSync(for: "\(wireName)") { data in
        try SwiftCBOR.CodableCBORDecoder().decode(Self.self, from: data)
    }
}()
```

### Benefits
1. **Matches Rust behavior exactly** - synchronous registration at startup
2. **Eliminates async complexity** - no more `await Self._ensureRegistered()`
3. **Fixes decryption-only scenarios** - types registered at startup, not first encryption
4. **Better performance** - no async overhead for one-time registration
5. **More reliable** - no timing issues or race conditions

### Implementation Steps
1. Add synchronous registration methods to `SerializationRegistry`
2. Update macro to use static initialization
3. Remove `_ensureRegistered()` calls from all methods
4. Fix unnecessary resolver call in tests
5. Remove hack of calling `encryptWithKeystore` just for registration

