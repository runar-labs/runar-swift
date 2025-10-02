import Foundation
import SwiftCBOR
import SwiftFFI

/// Envelope encryption utilities for the serializer
public enum EnvelopeEncryption {
    public static func encrypt(
        _ data: Data,
        context: SerializationContext
    ) async throws -> Data {
        // Use network public key directly from context
        return try await context.keystore.encryptWithEnvelope(data: data, networkPublicKey: context.networkPublicKey, profilePublicKeys: context.profilePublicKeys)
    }

    public static func decrypt(
        _ envelopeData: Data,
        context: SerializationContext,
        profileId: String? = nil
    ) async throws -> Data {
        if let pid = profileId, let nodeKeystore = context.keystore as? NodeOnly {
            try await nodeKeystore.decryptWithProfile(envelopeData: envelopeData, profileId: pid)
        } else {
            try await context.keystore.decryptEnvelope(envelopeData: envelopeData)
        }
    }
}
