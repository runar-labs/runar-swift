import Foundation
import SwiftCBOR
import SwiftFFI

/// Envelope encryption utilities for the serializer
public enum EnvelopeEncryption {
    public static func encrypt(
        _ data: Data,
        context: SerializationContext
    ) async throws -> Data {
        // Convert networkId string to Data (simplified conversion)
        let networkKey = Data(context.networkId.utf8)
        return try await context.keystore.encryptWithEnvelope(data: data, networkPublicKey: networkKey, profilePublicKeys: [])
    }

    public static func decrypt(
        _ envelopeData: Data,
        context: SerializationContext,
        profileId: String? = nil
    ) async throws -> Data {
        if let pid = profileId, let nodeKeystore = context.keystore as? NodeOnly {
            return try await nodeKeystore.decryptWithProfile(envelopeData: envelopeData, profileId: pid)
        } else {
            return try await context.keystore.decryptEnvelope(envelopeData: envelopeData)
        }
    }

}
