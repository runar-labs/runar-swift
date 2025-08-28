import Foundation
import RunarFFI

// Shared encryption-related types used across the serializer

public typealias EnvelopeEncryptedData = RunarFFI.EnvelopeEncryptedData
public typealias EnvelopeCrypto = RunarFFI.EnvelopeCrypto
public typealias KeyStore = RunarFFI.EnvelopeCrypto

public struct SerializationContext {
    public let keystore: EnvelopeCrypto
    public let resolver: RunarFFI.LabelResolver
    public let networkId: String
    public let profilePublicKey: Data?

    public init(keystore: EnvelopeCrypto, resolver: RunarFFI.LabelResolver, networkId: String, profilePublicKey: Data? = nil) {
        self.keystore = keystore
        self.resolver = resolver
        self.networkId = networkId
        self.profilePublicKey = profilePublicKey
    }
}
