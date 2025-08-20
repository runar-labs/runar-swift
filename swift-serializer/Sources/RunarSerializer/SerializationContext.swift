import Foundation

// Shared encryption-related types used across the serializer

public struct EnvelopeEncryptedData: Sendable, Equatable, Codable {
    public let encryptedData: Data
    public let networkId: String?
    public let networkEncryptedKey: Data
    public let profileEncryptedKeys: [String: Data]

    public init(encryptedData: Data, networkId: String?, networkEncryptedKey: Data, profileEncryptedKeys: [String: Data]) {
        self.encryptedData = encryptedData
        self.networkId = networkId
        self.networkEncryptedKey = networkEncryptedKey
        self.profileEncryptedKeys = profileEncryptedKeys
    }
}

public protocol EnvelopeCrypto: Sendable {
    func encryptWithEnvelope(data: Data, networkId: String?, profileIds: [String]) throws -> EnvelopeEncryptedData
    func decryptWithProfile(envelopeData: EnvelopeEncryptedData, profileId: String) throws -> Data
    func decryptWithNetwork(envelopeData: EnvelopeEncryptedData) throws -> Data
}

public typealias KeyStore = EnvelopeCrypto

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


