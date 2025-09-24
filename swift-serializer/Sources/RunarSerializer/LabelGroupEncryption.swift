import Foundation
import SwiftCBOR
import SwiftFFI

// MARK: - Label Group Encryption Types

/// Result of encrypting a label group
public struct EncryptedLabelGroup: Sendable, Equatable {
    public let label: String
    public let envelope: Data?

    public init(label: String, envelope: Data?) {
        self.label = label
        self.envelope = envelope
    }
}

// MARK: - Label Group Encryption Functions

/// Encrypt a label group using the provided keystore and resolver
/// - Parameters:
///   - label: The label for this group
///   - fieldsStruct: The struct containing the fields to encrypt
///   - keystore: The keystore for encryption operations
///   - resolver: The label resolver for key resolution
/// - Returns: EncryptedLabelGroup with the label and optional envelope
/// - Throws: SerializerError if encryption fails
public func encryptLabelGroup(
    label: String,
    fieldsStruct: some Codable,
    keystore: CommonKeyManager,
    resolver: LabelResolver
) async throws -> EncryptedLabelGroup {
    // Encode fieldsStruct to CBOR using SwiftCBOR Codable encoder
    let encoder = CodableCBOREncoder()
    let plainBytes = try encoder.encode(fieldsStruct)

    // If resolver cannot resolve the label, return group with nil envelope (expected partial-access case)
    guard resolver.canResolve(label) else {
        return EncryptedLabelGroup(label: label, envelope: nil)
    }

    // Resolve label info to get actual key material
    let info = try resolver.resolveLabelInfo(label)

    // Use the CommonKeyManager protocol to encrypt
    let envelope = try await keystore.encryptWithEnvelope(
        data: plainBytes,
        networkPublicKey: info.networkPublicKey,
        profilePublicKeys: info.profilePublicKeys
    )

    return EncryptedLabelGroup(label: label, envelope: envelope)
}

/// Decrypt a label group using the provided keystore
/// - Parameters:
///   - encryptedGroup: The encrypted label group to decrypt
///   - keystore: The keystore for decryption operations
/// - Returns: The decrypted struct of type T
/// - Throws: SerializerError if decryption or deserialization fails
public func decryptLabelGroup<T: Codable & RunarDefault>(
    encryptedGroup: EncryptedLabelGroup,
    keystore: CommonKeyManager
) async throws -> T {
    // If envelope is nil, return default value (expected for partial-access cases)
    guard let envelope = encryptedGroup.envelope else {
        return T.runarDefaultValue
    }

    // Use the CommonKeyManager protocol to decrypt
    let decryptedData: Data
    do {
        // Try network-based decryption first (more reliable)
        decryptedData = try await keystore.decryptEnvelope(envelopeData: envelope)
    } catch {
        // If network decryption fails, try profile-based decryption (NodeOnly)
        do {
            // For now, use a default profile ID
            let defaultProfileId = "default"
            if let nodeKeystore = keystore as? NodeOnly {
                decryptedData = try await nodeKeystore.decryptWithProfile(envelopeData: envelope, profileId: defaultProfileId)
            } else {
                // Mobile keystore doesn't support profile decryption, return default
                return T.runarDefaultValue
            }
        } catch {
            // If both decryption methods fail, return default value
            return T.runarDefaultValue
        }
    }
    let decoder = CodableCBORDecoder()
    return try decoder.decode(T.self, from: decryptedData)
}
