import Foundation
import SwiftFFI

// Shared encryption-related types used across the serializer

public typealias CommonKeyManager = SwiftFFI.CommonKeyManager

public struct SerializationContext {
    public let keystore: CommonKeyManager
    public let resolver: LabelResolver // Use the Swift-side label resolver
    public let networkId: String
    public let profilePublicKey: Data?

    public init(keystore: CommonKeyManager, resolver: LabelResolver, networkId: String, profilePublicKey: Data? = nil) {
        self.keystore = keystore
        self.resolver = resolver
        self.networkId = networkId
        self.profilePublicKey = profilePublicKey
    }
}
