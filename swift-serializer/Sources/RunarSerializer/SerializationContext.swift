import Foundation
#if canImport(RunarKeys)
import RunarKeys
#endif

// Shared encryption-related types used across the serializer

public typealias EnvelopeEncryptedData = RunarKeys.EnvelopeEncryptedData
public typealias KeyStore = RunarKeys.EnvelopeCrypto

public struct SerializationContext {
    public let keystore: EnvelopeCrypto
    public let resolver: LabelResolver
    public let networkId: String
    public let profilePublicKey: Data?

    public init(keystore: EnvelopeCrypto, resolver: LabelResolver, networkId: String, profilePublicKey: Data? = nil) {
        self.keystore = keystore
        self.resolver = resolver
        self.networkId = networkId
        self.profilePublicKey = profilePublicKey
    }
}


