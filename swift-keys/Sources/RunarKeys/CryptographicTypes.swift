import CryptoKit
import Foundation
import Security

// MARK: - Error Types

/// Cryptographic key and certificate errors
public enum KeyError: Error, LocalizedError {
    case invalidKeyFormat(String)
    case certificateError(String)
    case certificateNotFound(String)
    case encryptionError(String)
    case decryptionError(String)
    case keyDerivationError(String)
    case keyNotFound(String)
    case keyAlreadyInitialized(String)
    case signingError(String)
    case validationError(String)
    case invalidOperation(String)
    case keyGenerationFailed(String)
    case keychainOperationFailed(String)
    case certificateChainError(String)
    case secIdentityError(String)
    case secTrustError(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidKeyFormat(message):
            return "Invalid key format: \(message)"
        case let .certificateError(message):
            return "Certificate error: \(message)"
        case let .certificateNotFound(message):
            return "Certificate not found: \(message)"
        case let .encryptionError(message):
            return "Encryption error: \(message)"
        case let .decryptionError(message):
            return "Decryption error: \(message)"
        case let .keyDerivationError(message):
            return "Key derivation error: \(message)"
        case let .keyNotFound(message):
            return "Key not found: \(message)"
        case let .keyAlreadyInitialized(message):
            return "Key already initialized: \(message)"
        case let .signingError(message):
            return "Signing error: \(message)"
        case let .validationError(message):
            return "Validation error: \(message)"
        case let .invalidOperation(message):
            return "Invalid operation: \(message)"
        case let .keyGenerationFailed(message):
            return "Key generation failed: \(message)"
        case let .keychainOperationFailed(message):
            return "Keychain operation failed: \(message)"
        case let .certificateChainError(message):
            return "Certificate chain error: \(message)"
        case let .secIdentityError(message):
            return "SecIdentity error: \(message)"
        case let .secTrustError(message):
            return "SecTrust error: \(message)"
        }
    }
}

// MARK: - ECDH Key Pair (P-384)

/// ECDH Key Pair using P-384 curve (recommended for TLS 1.3)
/// This provides stronger security than P-256 and is recommended for TLS 1.3
/// ECDH keys can perform both key agreement (ECIES) and signing (ECDSA) operations
public struct ECDHKeyPair: Sendable {
    /// The primary ECDH private key for key agreement operations
    private let keyAgreementPrivateKey: P384.KeyAgreement.PrivateKey

    /// The corresponding public key
    public let publicKey: P384.KeyAgreement.PublicKey

    /// Initialize with a new random key pair
    public init() throws {
        keyAgreementPrivateKey = P384.KeyAgreement.PrivateKey()
        publicKey = keyAgreementPrivateKey.publicKey
    }

    /// Initialize from existing ECDH private key
    public init(keyAgreementPrivateKey: P384.KeyAgreement.PrivateKey) {
        self.keyAgreementPrivateKey = keyAgreementPrivateKey
        publicKey = keyAgreementPrivateKey.publicKey
    }

    /// Initialize from raw bytes (48-byte scalar for P-384)
    public init(rawRepresentation: Data) throws {
        keyAgreementPrivateKey = try P384.KeyAgreement.PrivateKey(rawRepresentation: rawRepresentation)
        publicKey = keyAgreementPrivateKey.publicKey
    }

    /// Initialize from Keychain SecKey (for TLS/QUIC integration)
    /// NOTE: This method is DEPRECATED and should not be used
    /// Use SecKey directly for Keychain operations instead
    @available(*, deprecated, message: "Use SecKey directly for Keychain operations. This wrapper creates a dummy private key.")
    public init(secKey _: SecKey) throws {
        throw KeyError.keychainOperationFailed("ECDHKeyPair(secKey:) is deprecated. Use SecKey directly for Keychain operations.")
    }

    /// Get the raw scalar bytes (48 bytes for P-384)
    public func rawScalarBytes() -> Data {
        return keyAgreementPrivateKey.rawRepresentation
    }

    /// Get public key as raw bytes (uncompressed point)
    public func publicKeyBytes() -> Data {
        return publicKey.x963Representation
    }

    /// Convert to ECDSA signing key for certificate operations
    public func toECDSASigningKey() throws -> P384.Signing.PrivateKey {
        return try P384.Signing.PrivateKey(rawRepresentation: keyAgreementPrivateKey.rawRepresentation)
    }

    /// Convert to ECDSA verifying key for certificate operations
    public func toECDSAVerifyingKey() throws -> P384.Signing.PublicKey {
        return try P384.Signing.PublicKey(rawRepresentation: publicKey.rawRepresentation)
    }

    /// Sign data using ECDSA (converts to signing key internally)
    public func sign(data: Data) throws -> Data {
        let signingKey = try toECDSASigningKey()
        let signature = try signingKey.signature(for: data)
        return signature.rawRepresentation
    }

    /// Verify signature using ECDSA (converts to verifying key internally)
    public func verify(signature: Data, for data: Data) throws -> Bool {
        let verifyingKey = try toECDSAVerifyingKey()
        let ecdsaSignature = try P384.Signing.ECDSASignature(rawRepresentation: signature)
        return verifyingKey.isValidSignature(ecdsaSignature, for: data)
    }

    /// Perform ECDH key agreement with another public key
    public func sharedSecret(with publicKey: P384.KeyAgreement.PublicKey) throws -> SharedSecret {
        return try keyAgreementPrivateKey.sharedSecretFromKeyAgreement(with: publicKey)
    }

    // MARK: - Keychain Integration Methods

    /// Generate a new P-384 private key directly in the Keychain and return the SecKey reference
    /// This is the preferred method for TLS/QUIC integration as it provides persistent storage
    public static func generateInKeychain(label: String) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 384,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrLabel as String: label,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecAttrCanSign as String: true,
            ],
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw KeyError.keychainOperationFailed("Failed to generate private key in Keychain: \(error?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }
        return secKey
    }

    /// Static ECIES encryption using recipient's public key (no private key needed)
    public static func encryptECIES(data: Data, recipientPublicKey: Data) throws -> Data {
        // Generate ephemeral key pair for ECDH
        let ephemeralPrivateKey = P384.KeyAgreement.PrivateKey()
        let ephemeralPublicKey = ephemeralPrivateKey.publicKey

        // Convert recipient's public key bytes to KeyAgreement.PublicKey
        // The recipientPublicKey should be in uncompressed SEC1 format (97 bytes for P-384)
        let recipientKey = try P384.KeyAgreement.PublicKey(x963Representation: recipientPublicKey)

        // Perform ECDH key exchange
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientKey)
        let sharedSecretBytes = sharedSecret.withUnsafeBytes { Data($0) }

        // Derive encryption key using HKDF-SHA-384 with fixed info label
        let encryptionKey = try deriveKey(from: sharedSecretBytes, info: "runar-v1:ecies:envelope-key")

        // Encrypt the data using AES-GCM
        let encryptedData = try encryptWithSymmetricKey(data, encryptionKey)

        // Return ephemeral public key + encrypted data
        let ephemeralPublicBytes = ephemeralPublicKey.x963Representation
        var result = ephemeralPublicBytes
        result.append(encryptedData)

        return result
    }

    /// Encrypt data using ECIES with recipient's public key
    public func encryptECIES(data: Data, recipientPublicKey: Data) throws -> Data {
        return try ECDHKeyPair.encryptECIES(data: data, recipientPublicKey: recipientPublicKey)
    }

    /// Decrypt data using ECIES with our private key
    public func decryptECIES(encryptedData: Data) throws -> Data {
        // Extract ephemeral public key (97 bytes uncompressed for P-384) and encrypted data
        guard encryptedData.count >= 97 else {
            throw KeyError.decryptionError("Encrypted data too short for ECIES")
        }

        let ephemeralPublicBytes = encryptedData.prefix(97)
        let encryptedPayload = encryptedData.dropFirst(97)

        // Reconstruct ephemeral public key
        // The ephemeral public key is stored in uncompressed format (97 bytes for P-384)
        let ephemeralPublicKey = try P384.KeyAgreement.PublicKey(x963Representation: ephemeralPublicBytes)

        // Perform ECDH key exchange using our private key
        let sharedSecret = try keyAgreementPrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        let sharedSecretBytes = sharedSecret.withUnsafeBytes { Data($0) }

        // Derive encryption key using HKDF-SHA-384 with fixed info label
        let encryptionKey = try ECDHKeyPair.deriveKey(from: sharedSecretBytes, info: "runar-v1:ecies:envelope-key")

        // Decrypt the data using AES-GCM
        return try ECDHKeyPair.decryptWithSymmetricKey(encryptedPayload, encryptionKey)
    }

    /// Derive key using HKDF
    private static func deriveKey(from sharedSecret: Data, info: String) throws -> Data {
        let infoData = info.data(using: .utf8)!
        let salt = Data() // Empty salt for HKDF

        let sharedSecretKey = SymmetricKey(data: sharedSecret)
        let derivedKey = HKDF<SHA384>.deriveKey(
            inputKeyMaterial: sharedSecretKey,
            salt: salt,
            info: infoData,
            outputByteCount: 32
        )

        return Data(derivedKey.withUnsafeBytes { $0 })
    }

    /// Encrypt data using AES-256-GCM
    private static func encryptWithSymmetricKey(_ data: Data, _ key: Data) throws -> Data {
        guard key.count == 32 else {
            throw KeyError.encryptionError("Key must be 32 bytes for AES-256")
        }

        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
        return sealedBox.combined!
    }

    /// Decrypt data using AES-256-GCM
    private static func decryptWithSymmetricKey(_ data: Data, _ key: Data) throws -> Data {
        guard key.count == 32 else {
            throw KeyError.decryptionError("Key must be 32 bytes for AES-256")
        }

        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }
}

// MARK: - Deterministic Key Derivation (HKDF-SHA-384)

/// Utilities for deriving child keys (signing/agreement/storage) from a master scalar (P-384)
enum KeyDeriver {
    private static let derivationSalt = "RunarKeyDerivationSalt/v1".data(using: .utf8)!

    /// Derive a P-384 signing private key from a master scalar
    static func deriveSigningPrivateKey(masterScalar: Data, scope: String, label: String, counterStart: UInt32 = 0) throws -> P384.Signing.PrivateKey {
        var counter = counterStart
        while true {
            let infoString = "runar-v1:\(scope):signing:\(label)\(counter == 0 ? "" : ":\(counter)")"
            let info = infoString.data(using: .utf8)!
            let derivedBytes = try hkdf(ikm: masterScalar, info: info, outputLength: 48)
            if let key = try? P384.Signing.PrivateKey(rawRepresentation: derivedBytes) {
                return key
            }
            counter &+= 1
        }
    }

    /// Derive a P-384 agreement private key from a master scalar
    static func deriveAgreementPrivateKey(masterScalar: Data, scope: String, label: String, counterStart: UInt32 = 0) throws -> P384.KeyAgreement.PrivateKey {
        var counter = counterStart
        while true {
            let infoString = "runar-v1:\(scope):agreement:\(label)\(counter == 0 ? "" : ":\(counter)")"
            let info = infoString.data(using: .utf8)!
            let derivedBytes = try hkdf(ikm: masterScalar, info: info, outputLength: 48)
            if let key = try? P384.KeyAgreement.PrivateKey(rawRepresentation: derivedBytes) {
                return key
            }
            counter &+= 1
        }
    }

    /// Derive a storage key (32 bytes) from a master scalar
    static func deriveStorageKey(masterScalar: Data, scope: String, label: String) throws -> Data {
        let infoString = "runar-v1:\(scope):storage:\(label)"
        let info = infoString.data(using: .utf8)!
        return try hkdf(ikm: masterScalar, info: info, outputLength: 32)
    }

    private static func hkdf(ikm: Data, info: Data, outputLength: Int) throws -> Data {
        let key = SymmetricKey(data: ikm)
        let derivedKey = HKDF<SHA384>.deriveKey(
            inputKeyMaterial: key,
            salt: derivationSalt,
            info: info,
            outputByteCount: outputLength
        )
        return derivedKey.withUnsafeBytes { Data($0) }
    }
}

// MARK: - Codable Support

public extension ECDHKeyPair {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let privateKeyData = try container.decode(Data.self)

        let keyAgreementPrivateKey = try P384.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        self.init(keyAgreementPrivateKey: keyAgreementPrivateKey)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(keyAgreementPrivateKey.rawRepresentation)
    }
}
