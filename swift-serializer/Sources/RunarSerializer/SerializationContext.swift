import Foundation
import SwiftFFI

// Shared encryption-related types used across the serializer

public typealias CommonKeyManager = SwiftFFI.CommonKeyManager

public struct SerializationContext {
    public let keystore: CommonKeyManager
    public let resolver: LabelResolver // Use the Swift-side label resolver
    public let networkPublicKey: Data // ← PRE-RESOLVED PUBLIC KEY (matches Rust)
    public let profilePublicKeys: [Data] // ← MULTIPLE PROFILE KEYS (matches Rust)

    public init(keystore: CommonKeyManager, resolver: LabelResolver, networkPublicKey: Data, profilePublicKeys: [Data]) {
        self.keystore = keystore
        self.resolver = resolver
        self.networkPublicKey = networkPublicKey
        self.profilePublicKeys = profilePublicKeys
    }
}
