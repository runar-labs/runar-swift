import Foundation

public protocol EnvelopeCrypto {
    func encryptWithEnvelope(data: Data, networkId: String?, profileIds: [String]) throws -> EnvelopeEncryptedData
    func decryptWithProfile(envelopeData: EnvelopeEncryptedData, profileId: String) throws -> Data
    func decryptWithNetwork(envelopeData: EnvelopeEncryptedData) throws -> Data
}

extension MobileKeyManager: EnvelopeCrypto {}


