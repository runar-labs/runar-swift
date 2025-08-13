import CryptoKit
import Foundation
import Security
import SwiftASN1
import X509

/// Setup token from a node requesting a certificate
public struct SetupToken: Codable {
    /// Node's public key for identity
    public let nodePublicKey: Data
    /// Node's certificate signing request (CSR) in DER format
    public let csrDer: Data
    /// Node identifier string
    public let nodeId: String

    public init(nodePublicKey: Data, csrDer: Data, nodeId: String) {
        self.nodePublicKey = nodePublicKey
        self.csrDer = csrDer
        self.nodeId = nodeId
    }
}

/// Secure message containing certificate and CA information for a node
public struct NodeCertificateMessage: Codable {
    /// The signed certificate for the node
    public let nodeCertificate: X509Certificate
    /// The CA certificate for validation
    public let caCertificate: X509Certificate
    /// Additional metadata
    public let metadata: CertificateMetadata

    public init(nodeCertificate: X509Certificate, caCertificate: X509Certificate, metadata: CertificateMetadata) {
        self.nodeCertificate = nodeCertificate
        self.caCertificate = caCertificate
        self.metadata = metadata
    }
}

/// Certificate metadata
public struct CertificateMetadata: Codable {
    /// Issue timestamp
    public let issuedAt: UInt64
    /// Validity period in days
    public let validityDays: UInt32
    /// Certificate purpose
    public let purpose: String

    public init(issuedAt: UInt64, validityDays: UInt32, purpose: String) {
        self.issuedAt = issuedAt
        self.validityDays = validityDays
        self.purpose = purpose
    }
}

/// Network key information for secure node communication
public struct NetworkKeyMessage: Codable {
    /// Network identifier
    public let networkId: String
    /// Network public key
    public let networkPublicKey: Data
    /// Encrypted network data key
    public let encryptedNetworkKey: Data
    /// Key derivation information
    public let keyDerivationInfo: String

    public init(networkId: String, networkPublicKey: Data, encryptedNetworkKey: Data, keyDerivationInfo: String) {
        self.networkId = networkId
        self.networkPublicKey = networkPublicKey
        self.encryptedNetworkKey = encryptedNetworkKey
        self.keyDerivationInfo = keyDerivationInfo
    }
}

/// QUIC certificate configuration for transport layer
public struct QuicCertificateConfig {
    /// Certificate chain (node certificate + CA certificate)
    public let certificateChain: [Data]
    /// SecKey reference for the node certificate (for SecIdentity creation)
    public let secKey: SecKey
    /// Certificate validator for peer certificates
    public let certificateValidator: CertificateValidator

    public init(certificateChain: [Data], secKey: SecKey, certificateValidator: CertificateValidator) {
        self.certificateChain = certificateChain
        self.secKey = secKey
        self.certificateValidator = certificateValidator
    }
}

/// Envelope encrypted data structure
public struct EnvelopeEncryptedData: Codable {
    /// The encrypted data payload
    public let encryptedData: Data
    /// Network ID this data belongs to
    public let networkId: String?
    /// Envelope key encrypted with network key (always required)
    public let networkEncryptedKey: Data
    /// Envelope key encrypted with each profile key
    public let profileEncryptedKeys: [String: Data]

    public init(encryptedData: Data, networkId: String?, networkEncryptedKey: Data, profileEncryptedKeys: [String: Data]) {
        self.encryptedData = encryptedData
        self.networkId = networkId
        self.networkEncryptedKey = networkEncryptedKey
        self.profileEncryptedKeys = profileEncryptedKeys
    }
}

/// Serializable snapshot of the MobileKeyManager for Keychain persistence
/// This allows persisting all cryptographic material so a restored instance
/// can continue to operate without regenerating or losing keys.
public struct MobileKeyManagerState: Codable {
    let caKeyPair: Data // Serialized ECDHKeyPair
    let caCertificate: Data // DER-encoded X509 certificate
    let userRootKey: Data? // Serialized ECDHKeyPair (optional)
    let userProfileKeys: [String: Data] // Profile ID -> Serialized ECDHKeyPair
    let labelToPid: [String: String] // Label -> Profile ID mapping
    let networkDataKeys: [String: Data] // Network ID -> Serialized ECDHKeyPair
    let networkPublicKeys: [String: Data] // Network ID -> Public key bytes
    let issuedCertificates: [String: Data] // Node ID -> DER-encoded certificate
    let certificateKeyLabels: [String: String] // Node ID -> Keychain key label
    let certificateKeyPairs: [String: Data] // Node ID -> Serialized ECDHKeyPair
    let certificateSecKeyLabels: [String: String] // Node ID -> Keychain key label for SecKey retrieval
    let serialCounter: UInt64

    public init(
        caKeyPair: Data,
        caCertificate: Data,
        userRootKey: Data?,
        userProfileKeys: [String: Data],
        labelToPid: [String: String],
        networkDataKeys: [String: Data],
        networkPublicKeys: [String: Data],
        issuedCertificates: [String: Data],
        certificateKeyLabels: [String: String],
        certificateKeyPairs: [String: Data],
        certificateSecKeyLabels: [String: String],
        serialCounter: UInt64
    ) {
        self.caKeyPair = caKeyPair
        self.caCertificate = caCertificate
        self.userRootKey = userRootKey
        self.userProfileKeys = userProfileKeys
        self.labelToPid = labelToPid
        self.networkDataKeys = networkDataKeys
        self.networkPublicKeys = networkPublicKeys
        self.issuedCertificates = issuedCertificates
        self.certificateKeyLabels = certificateKeyLabels
        self.certificateKeyPairs = certificateKeyPairs
        self.certificateSecKeyLabels = certificateSecKeyLabels
        self.serialCounter = serialCounter
    }
}

/// Mobile Key Manager that acts as a Certificate Authority
public class MobileKeyManager {
    /// Certificate Authority for issuing certificates
    private var certificateAuthority: CertificateAuthority
    /// Certificate validator
    private var certificateValidator: CertificateValidator
    /// User root key - Master key for the user (never leaves mobile)
    private var userRootKey: ECDHKeyPair?
    /// User profile agreement keys indexed by profile ID - derived from root key
    private var userProfileKeys: [String: ECDHKeyPair] = [:]
    /// User profile signing scalars indexed by label (for CSR/signature usage)
    private var userProfileSigningScalars: [String: Data] = [:]
    /// Mapping from human-readable label → compact-id for quick reuse
    private var labelToPid: [String: String] = [:]
    /// Network data keys indexed by network ID - for envelope encryption and decryption
    private var networkDataKeys: [String: ECDHKeyPair] = [:]
    /// Network public keys indexed by network ID - for envelope encryption
    private var networkPublicKeys: [String: Data] = [:]
    /// Issued certificates tracking
    private var issuedCertificates: [String: X509Certificate] = [:]
    /// Keychain labels for issued certificate private keys
    private var certificateKeyLabels: [String: String] = [:]
    /// In-memory key pairs for issued certificates (to avoid Keychain export issues)
    private var certificateKeyPairs: [String: ECDHKeyPair] = [:]
    /// Certificate SecKey references for direct Keychain access
    private var certificateSecKeys: [String: SecKey] = [:]
    /// Monotonically-increasing certificate serial number
    private var serialCounter: UInt64 = 1
    /// Logger instance
    private let logger: Logger

    /// Keychain service identifier for this app
    private let keychainService = "com.runar.keys"
    /// Keychain account identifier for the mobile key manager state
    private let keychainAccount = "MobileKeyManagerState"

    /// Create a new Mobile Key Manager
    public init(logger: Logger) throws {
        // Create a temporary certificate authority (will be replaced when CA is created)
        let caSubject = "CN=Temp,O=Runar,C=US"
        certificateAuthority = try CertificateAuthority.create(subject: caSubject)

        // Create certificate validator with the temporary CA certificate
        let caCert = certificateAuthority.certificate
        certificateValidator = CertificateValidator(trustedCaCertificates: [caCert])

        self.logger = logger
        logger.info("Mobile Key Manager initialized")
    }

    /// Install a network public key
    public func installNetworkPublicKey(_ networkPublicKey: Data) throws {
        let networkId = CryptoUtils.compactId(networkPublicKey)
        networkPublicKeys[networkId] = networkPublicKey

        logger.info("Network public key installed with ID: \(networkId)")
    }

    /// Generate a network data key for envelope encryption and return the network ID (compact Base64 public key)
    public func generateNetworkDataKey() throws -> String {
        let networkKey = try ECDHKeyPair()
        let publicKey = networkKey.publicKeyBytes()
        let networkId = CryptoUtils.compactId(publicKey)

        networkDataKeys[networkId] = networkKey
        logger.info("Network data key generated with ID: \(networkId)")

        return networkId
    }

    /// Deterministically derive a network data key using a stable label. Returns the network ID.
    public func deriveNetworkDataKey(label: String) throws -> String {
        guard let rootKey = userRootKey else {
            throw KeyError.keyNotFound("User root key not initialized")
        }
        let rootScalarBytes = rootKey.rawScalarBytes()
        let agreementPriv = try KeyDeriver.deriveAgreementPrivateKey(
            masterScalar: rootScalarBytes,
            scope: "network",
            label: label
        )
        let networkKey = ECDHKeyPair(keyAgreementPrivateKey: agreementPriv)
        let publicKey = networkKey.publicKeyBytes()
        let networkId = CryptoUtils.compactId(publicKey)
        networkDataKeys[networkId] = networkKey
        logger.info("Network data key derived with ID: \(networkId) (label: \(label))")
        return networkId
    }

    /// Get network public key by network ID
    public func getNetworkPublicKey(networkId: String) throws -> Data {
        // Check both network_data_keys and network_public_keys
        if let networkKey = networkDataKeys[networkId] {
            return networkKey.publicKeyBytes()
        } else if let networkPublicKey = networkPublicKeys[networkId] {
            return networkPublicKey
        } else {
            throw KeyError.keyNotFound("Network public key not found for network: \(networkId)")
        }
    }

    /// Process a setup token from a node and issue a certificate
    public func processSetupToken(_ setupToken: SetupToken) throws -> NodeCertificateMessage {
        let nodeId = setupToken.nodeId
        logger.info("Processing setup token for node: \(nodeId)")

        // Enforce CSR presence and non-empty
        guard !setupToken.csrDer.isEmpty else {
            throw KeyError.invalidOperation("CSR is required and must not be empty")
        }

        // Parse CSR
        let csr = try CertificateRequest(derData: setupToken.csrDer)

        // Verify proof-of-possession by checking the CSR signature
        // swift-certificates verifies CSR signature during parsing; additional checks could be added if needed

        // Validate subject CN matches DNS-safe node id (exact match)
        let subjectDescription = csr.subject
        let expectedCN = dnsSafeName(nodeId)
        guard subjectDescription.contains("CN=\(expectedCN)") else {
            throw KeyError.validationError("CSR CN must exactly match DNS-safe node id")
        }

        // Issue certificate from CSR with monotonic serial number increment
        let validityDays: UInt32 = 365 // 1-year validity (consider shortening)
        // Pre-allocate next serial, persist immediately to avoid reuse after crash
        let allocatedSerialCounter = serialCounter &+ 1
        serialCounter = allocatedSerialCounter
        // Best-effort persist; do not fail issuance if persistence fails
        do { try saveToKeychain() } catch { logger.warn("Failed to persist serialCounter pre-allocation: \(error)") }

        // Build monotonic serial (big-endian, positive, <= 20 bytes) from allocated value
        var serialBytes = withUnsafeBytes(of: allocatedSerialCounter.bigEndian, Array.init)
        // Trim leading zeros to keep it short; ensure at least 1 byte
        while serialBytes.first == 0, serialBytes.count > 1 {
            serialBytes.removeFirst()
        }
        let serial = Certificate.SerialNumber(bytes: ArraySlice(serialBytes))

        let nodeCertificate = try certificateAuthority.signCertificateRequest(
            csrDer: setupToken.csrDer,
            validityDays: Int(validityDays),
            serialNumber: serial
        )

        // serialCounter was already incremented and persisted before issuance

        // Store the issued certificate
        issuedCertificates[nodeId] = nodeCertificate

        // Create metadata
        let metadata = CertificateMetadata(
            issuedAt: UInt64(Date().timeIntervalSince1970),
            validityDays: validityDays,
            purpose: "Node TLS Certificate"
        )

        // Create the message
        return NodeCertificateMessage(
            nodeCertificate: nodeCertificate,
            caCertificate: certificateAuthority.certificate,
            metadata: metadata
        )
    }

    /// Validate a certificate issued by this CA
    public func validateCertificate(_ certificate: X509Certificate) throws {
        try certificateValidator.validateCertificate(certificate)
    }

    /// Get issued certificate by node ID
    public func getIssuedCertificate(nodeId: String) -> X509Certificate? {
        issuedCertificates[nodeId]
    }

    /// List all issued certificates
    public func listIssuedCertificates() -> [(String, X509Certificate)] {
        issuedCertificates.map { nodeId, cert in (nodeId, cert) }
    }

    /// Create a fresh 32-byte symmetric key for envelope encryption
    private func createEnvelopeKey() -> Data {
        var envelopeKey = Data(count: 32)
        envelopeKey.withUnsafeMutableBytes { bytes in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        return envelopeKey
    }

    /// Encrypt data with symmetric key using AES-GCM
    private func encryptWithSymmetricKey(_ data: Data, _ key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined ?? Data()
    }

    /// Decrypt data with symmetric key using AES-GCM
    private func decryptWithSymmetricKey(_ encryptedData: Data, _ key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: key)
    }

    /// Helper methods for symmetric encryption using AES-256-GCM
    private func encryptWithSymmetricKey(_ data: Data, _ key: Data) throws -> Data {
        guard key.count == 32 else {
            throw KeyError.encryptionError("Key must be 32 bytes for AES-256")
        }

        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
        return sealedBox.combined!
    }

    private func decryptWithSymmetricKey(_ encryptedData: Data, _ key: Data) throws -> Data {
        guard key.count == 32 else {
            throw KeyError.decryptionError("Key must be 32 bytes for AES-256")
        }

        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let symmetricKey = SymmetricKey(data: key)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    /// Encrypt data with envelope encryption
    /// This implements the envelope encryption pattern:
    /// 1. Generate ephemeral envelope key
    /// 2. Encrypt data with envelope key
    /// 3. Encrypt envelope key with network/profile keys
    public func encryptWithEnvelope(
        data: Data,
        networkId: String?,
        profileIds: [String]
    ) throws -> EnvelopeEncryptedData {
        // Validate that we have at least one key to encrypt the envelope key with
        let hasNetworkKey = networkId != nil
        let hasProfileKeys = !profileIds.isEmpty && profileIds.contains { userProfileKeys[$0] != nil }

        if !hasNetworkKey, !hasProfileKeys {
            throw KeyError.invalidOperation("No valid network or profile keys provided for envelope encryption")
        }

        // Generate ephemeral envelope key
        let envelopeKeyData = createEnvelopeKey()

        // Encrypt data with envelope key (using AES-GCM)
        let encryptedData = try encryptWithSymmetricKey(data, envelopeKeyData)

        // Encrypt envelope key for network (optional)
        var networkEncryptedKey = Data()
        if let networkId, let networkKey = networkDataKeys[networkId] {
            let pk = networkKey.publicKeyBytes()
            // Encrypt the envelope key with network key's public key
            networkEncryptedKey = try ECDHKeyPair.encryptECIES(data: envelopeKeyData, recipientPublicKey: pk)
        } else if let networkId, let networkPublicKeyBytes = networkPublicKeys[networkId] {
            // Use static method for encryption
            networkEncryptedKey = try ECDHKeyPair.encryptECIES(data: envelopeKeyData, recipientPublicKey: networkPublicKeyBytes)
        }

        // Encrypt envelope key for each profile
        var profileEncryptedKeys: [String: Data] = [:]
        for profileId in profileIds {
            if let profileKey = userProfileKeys[profileId] {
                let pk = profileKey.publicKeyBytes()
                // Encrypt the envelope key with profile key's public key
                let encryptedKey = try ECDHKeyPair.encryptECIES(data: envelopeKeyData, recipientPublicKey: pk)
                profileEncryptedKeys[profileId] = encryptedKey
            }
        }

        return EnvelopeEncryptedData(
            encryptedData: encryptedData,
            networkId: networkId,
            networkEncryptedKey: networkEncryptedKey,
            profileEncryptedKeys: profileEncryptedKeys
        )
    }

    /// Decrypt envelope-encrypted data using profile key
    public func decryptWithProfile(
        envelopeData: EnvelopeEncryptedData,
        profileId: String
    ) throws -> Data {
        guard let profileKey = userProfileKeys[profileId] else {
            throw KeyError.keyNotFound("Profile key not found: \(profileId)")
        }

        guard let encryptedEnvelopeKey = envelopeData.profileEncryptedKeys[profileId] else {
            throw KeyError.keyNotFound("Envelope key not found for profile: \(profileId)")
        }

        // Decrypt the envelope key using profile key
        let envelopeKey = try profileKey.decryptECIES(encryptedData: encryptedEnvelopeKey)

        // Decrypt the data using the recovered envelope key
        return try decryptWithSymmetricKey(envelopeData.encryptedData, envelopeKey)
    }

    /// Decrypt envelope-encrypted data using network key
    public func decryptWithNetwork(
        envelopeData: EnvelopeEncryptedData
    ) throws -> Data {
        guard let networkId = envelopeData.networkId else {
            throw KeyError.decryptionError("Envelope missing network_id")
        }

        guard let networkKey = networkDataKeys[networkId] else {
            throw KeyError.keyNotFound("Network key pair not found for network: \(networkId)")
        }

        let encryptedEnvelopeKey = envelopeData.networkEncryptedKey

        if encryptedEnvelopeKey.isEmpty {
            throw KeyError.decryptionError("Envelope missing network_encrypted_key")
        }

        // Decrypt the envelope key using network key
        let envelopeKey = try networkKey.decryptECIES(encryptedData: encryptedEnvelopeKey)

        // Decrypt the data using the recovered envelope key
        return try decryptWithSymmetricKey(envelopeData.encryptedData, envelopeKey)
    }

    /// Initialize user root key - Master key that never leaves the mobile device
    public func initializeUserRootKey() throws -> Data {
        if userRootKey != nil {
            throw KeyError.keyAlreadyInitialized("User root key already initialized")
        }

        let rootKey = try ECDHKeyPair()
        let publicKey = rootKey.publicKeyBytes()

        userRootKey = rootKey
        logger.info("User root key initialized (private key secured on mobile)")

        return publicKey
    }

    /// Create CA certificate - Only call this on the designated CA
    public func createCACertificate() throws {
        // Check if CA certificate already exists
        if certificateAuthority.certificate.subject.contains("Runar User CA") {
            logger.info("CA certificate already exists")
            return
        }

        // Create Certificate Authority with user identity
        let caSubject = "CN=Runar User CA,O=Runar,C=US"
        certificateAuthority = try CertificateAuthority.create(subject: caSubject)

        // Create certificate validator with the CA certificate
        let caCert = certificateAuthority.certificate
        certificateValidator = CertificateValidator(trustedCaCertificates: [caCert])

        logger.info("CA certificate created successfully")
    }

    /// Get the user root public key
    public func getUserRootPublicKey() throws -> Data {
        guard let rootKey = userRootKey else {
            throw KeyError.keyNotFound("User root key not initialized")
        }
        return rootKey.publicKeyBytes()
    }

    /// Get the user CA certificate
    public func getCaCertificate() -> X509Certificate {
        certificateAuthority.certificate
    }

    /// Get the CA public key bytes
    public func getCaPublicKey() -> Data {
        try! certificateAuthority.getKeyPair().toECDSAVerifyingKey().x963Representation
    }

    /// Derive a user profile key from the root key using HKDF.
    ///
    /// This implementation follows these steps:
    /// 1. The secret scalar bytes of the user root key are used as the
    ///    Input Key Material (IKM) for HKDF-SHA-256.
    /// 2. A domain-separated `info` string (`"runar-profile-{label}"`)
    ///    is supplied to HKDF to ensure every profile receives a unique key
    ///    tied to the caller-supplied identifier.
    /// 3. HKDF expands to 32 bytes. These bytes are interpreted as a P-256
    ///    scalar. If the candidate scalar is not in the valid field range
    ///    (i.e. ≥ n or zero) we derive a new candidate by appending an
    ///    incrementing counter to the `info` string.
    /// 4. The resulting scalar is converted into an ECDHKeyPair which is
    ///    cached so subsequent calls for the same `label` return the
    ///    exact same key without additional computation.
    ///
    /// This approach is deterministic, collision-resistant, and ensures strong
    /// cryptographic separation between the root and profile keys while
    /// remaining compatible with the system-wide ECDSA P-256 algorithm.
    public func deriveUserProfileKey(label: String) throws -> Data {
        // Fast-path: if we already derived a key for this label return it.
        if let pid = labelToPid[label] {
            if let key = userProfileKeys[pid] {
                return key.publicKeyBytes()
            }
        }

        // Ensure the root key exists.
        guard let rootKey = userRootKey else {
            throw KeyError.keyNotFound("User root key not initialized")
        }

        // Extract the raw 48-byte scalar of the root private key (P-384).
        let rootScalarBytes = rootKey.rawScalarBytes()

        // Derive agreement and signing keys deterministically via centralized KeyDeriver (aligned salt/info)
        let agreementPriv = try KeyDeriver.deriveAgreementPrivateKey(masterScalar: rootScalarBytes, scope: "profile", label: label)
        let signingPriv = try KeyDeriver.deriveSigningPrivateKey(masterScalar: rootScalarBytes, scope: "profile", label: label)
        let profileKey = ECDHKeyPair(keyAgreementPrivateKey: agreementPriv)
        userProfileSigningScalars[label] = signingPriv.rawRepresentation

        // Cache the profile key using the compact ID.
        let publicKey = profileKey.publicKeyBytes()
        let pid = CryptoUtils.compactId(publicKey)
        userProfileKeys[pid] = profileKey
        labelToPid[label] = pid

        logger.info("User profile key derived using HKDF for label '\(label)' (id: \(pid))")

        return publicKey
    }

    /// Get the profile ID (PID) for a given label
    public func getProfileId(for label: String) throws -> String {
        if let pid = labelToPid[label] {
            return pid
        }

        // If not found, derive the profile key first
        _ = try deriveUserProfileKey(label: label)

        // Now it should be in the mapping
        guard let pid = labelToPid[label] else {
            throw KeyError.keyNotFound("Profile ID not found for label: \(label)")
        }

        return pid
    }

    /// Get statistics about the mobile key manager
    public func getStatistics() -> MobileKeyManagerStatistics {
        MobileKeyManagerStatistics(
            issuedCertificatesCount: issuedCertificates.count,
            userProfileKeysCount: userProfileKeys.count,
            networkKeysCount: networkDataKeys.count,
            caCertificateSubject: certificateAuthority.certificate.subject
        )
    }

    /// Normalize arbitrary input into a DNS-safe label (lowercase, allowed chars [a-z0-9-.])
    private func dnsSafeName(_ input: String) -> String {
        let lowered = input.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        let filtered = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var result = String(filtered)
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "node" : result
    }

    // MARK: - Legacy Compatibility Methods

    /// Initialize user identity and generate root keys (legacy method)
    public func initializeUserIdentity() throws -> Data {
        try initializeUserRootKey()
    }

    /// Encrypt data for a specific profile (legacy method for compatibility)
    public func encryptForProfile(data: Data, profileId: String) throws -> Data {
        // Use envelope encryption with just this profile
        let envelopeData = try encryptWithEnvelope(
            data: data,
            networkId: nil,
            profileIds: [profileId]
        )
        // Return just the encrypted data for compatibility
        return envelopeData.encryptedData
    }

    /// Encrypt data for a network (legacy method for compatibility)
    public func encryptForNetwork(data: Data, networkId: String) throws -> Data {
        // Use envelope encryption with just this network
        let envelopeData = try encryptWithEnvelope(
            data: data,
            networkId: networkId,
            profileIds: []
        )
        // Return just the encrypted data for compatibility
        return envelopeData.encryptedData
    }

    /// Generate a user profile key (legacy method name for compatibility)
    public func generateUserProfileKey(profileId: String) throws -> Data {
        try deriveUserProfileKey(label: profileId)
    }

    // MARK: - Node Communication Methods

    /// Create a network key message for a node with proper encryption
    public func createNetworkKeyMessage(networkId: String, nodePublicKey: Data) throws -> NetworkKeyMessage {
        guard let networkKey = networkDataKeys[networkId] else {
            throw KeyError.keyNotFound("Network key pair not found for network: \(networkId)")
        }

        // Encrypt the network's private key for the node
        let networkPrivateKey = networkKey.rawScalarBytes()
        let encryptedNetworkKey = try ECDHKeyPair.encryptECIES(data: networkPrivateKey, recipientPublicKey: nodePublicKey)

        let nodeId = CryptoUtils.compactId(nodePublicKey)
        logger.info("Network key encrypted for node \(nodeId) with ECIES")

        return NetworkKeyMessage(
            networkId: networkId,
            networkPublicKey: networkKey.publicKeyBytes(),
            encryptedNetworkKey: encryptedNetworkKey,
            keyDerivationInfo: "Network key for node \(nodeId) (ECIES encrypted)"
        )
    }

    /// Encrypt a message for a node using its public key (ECIES)
    public func encryptMessageForNode(message: Data, nodePublicKey: Data) throws -> Data {
        let messageLen = message.count
        logger.debug("Encrypting message for node (\(messageLen) bytes)")
        return try ECDHKeyPair.encryptECIES(data: message, recipientPublicKey: nodePublicKey)
    }

    /// Decrypt a message from a node using the user's root key (ECIES)
    public func decryptMessageFromNode(encryptedMessage: Data) throws -> Data {
        let encryptedMessageLen = encryptedMessage.count
        logger.debug("Decrypting message from node (\(encryptedMessageLen) bytes)")

        guard let rootKeyPair = userRootKey else {
            throw KeyError.keyNotFound("User root key not initialized")
        }

        return try rootKeyPair.decryptECIES(encryptedData: encryptedMessage)
    }

    // MARK: - Node Key Manager Compatibility Methods

    /// Node certificate status
    public enum CertificateStatus {
        case none
        case pending
        case valid
        case invalid
    }

    /// Get the node public key (for compatibility with NodeKeyManager)
    public func getNodePublicKey() -> Data {
        // For mobile, this is the user root key public key
        try! getUserRootPublicKey()
    }

    /// Get the node ID (compact Base58 encoding of public key)
    public func getNodeId() -> String {
        let publicKey = getNodePublicKey()
        return CryptoUtils.compactId(publicKey)
    }

    /// Get certificate status
    public func getCertificateStatus() -> CertificateStatus {
        // Mobile always has a valid CA certificate
        .valid
    }

    /// Generate a CSR (Certificate Signing Request) for node setup
    /// This follows the POC pattern: generate key in Keychain first, then create certificate
    public func generateCSR() throws -> SetupToken {
        let nodeId = getNodeId()

        // 1) Generate P-384 key pair directly in Keychain (software token)
        let keyLabel = "Runar Node Private Key \(nodeId)"
        let appTag = Data(("com.runar.keys." + nodeId).utf8)

        let privateAttrs: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: appTag,
            kSecAttrLabel as String: keyLabel,
        ]
        let genParams: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 384,
            kSecPrivateKeyAttrs as String: privateAttrs,
        ]
        var genError: Unmanaged<CFError>?
        guard let secPrivateKey = SecKeyCreateRandomKey(genParams as CFDictionary, &genError) else {
            let msg = genError?.takeRetainedValue().localizedDescription ?? "Unknown"
            throw KeyError.keychainOperationFailed("SecKeyCreateRandomKey failed: \(msg)")
        }
        guard let secPublicKey = SecKeyCopyPublicKey(secPrivateKey) else {
            throw KeyError.keychainOperationFailed("Failed to copy public key from private key")
        }

        // 2) Export public key (x963) for identity/peer info
        var pubErr: Unmanaged<CFError>?
        guard let publicKeyBytes = SecKeyCopyExternalRepresentation(secPublicKey, &pubErr) as Data? else {
            let msg = pubErr?.takeRetainedValue().localizedDescription ?? "Unknown"
            throw KeyError.keychainOperationFailed("Failed to export public key: \(msg)")
        }

        // 3) Export private key external representation and derive signer scalar for CSR
        var privErr: Unmanaged<CFError>?
        guard let privExternal = SecKeyCopyExternalRepresentation(secPrivateKey, &privErr) as Data? else {
            let msg = privErr?.takeRetainedValue().localizedDescription ?? "Unknown"
            throw KeyError.keychainOperationFailed("Failed to export private key: \(msg)")
        }
        let signingScalar: Data
        if privExternal.count >= 48 && privExternal.first != 0x30 {
            signingScalar = Data(privExternal.suffix(48))
        } else if let parsed = extractP384PrivateScalar(fromECPrivateKeyExternal: privExternal) {
            signingScalar = parsed
        } else {
            throw KeyError.keychainOperationFailed("Unsupported EC private key external format for CSR signing")
        }

        // 4) Store label and SecKey for later use (SecIdentity pairing after cert issuance)
        certificateKeyLabels[nodeId] = keyLabel
        certificateSecKeys[nodeId] = secPrivateKey

        // 5) Build a PKCS#10 CSR with CN = DNS-safe node id; SANs computed server-side
        let subjectCN = dnsSafeName(nodeId)
        let subject = "CN=\(subjectCN),O=Runar,C=US"
        let ecdhKeyForCsr = try ECDHKeyPair(rawRepresentation: signingScalar)
        let csrDer = try CertificateRequest.create(keyPair: ecdhKeyForCsr, subject: subject)

        return SetupToken(
            nodePublicKey: publicKeyBytes,
            csrDer: csrDer,
            nodeId: nodeId
        )
    }

    /// Install a certificate received from mobile CA
    public func installCertificate(_ certMessage: NodeCertificateMessage) throws {
        // Update validator to trust the CA that issued this certificate
        certificateValidator = CertificateValidator(trustedCaCertificates: [certMessage.caCertificate])
        // Validate the certificate against the provided CA
        try validateCertificate(certMessage.nodeCertificate)

        // Import certificates into Keychain so SecIdentity can pair the leaf with its private key
        let nodeId = getNodeId()
        // Import leaf certificate with generic and node-specific labels
        // Import leaf certificate under node-specific label only to avoid accidental mismatches
        _ = try certMessage.nodeCertificate.importToKeychain(label: "Runar Node Certificate \(nodeId)")
        // Ensure CA certificate is also present (idempotent add)
        _ = try certMessage.caCertificate.importToKeychain(label: "Runar CA Certificate")

        // Store the certificate
        issuedCertificates[nodeId] = certMessage.nodeCertificate

        logger.info("Certificate installed for node: \(nodeId)")
    }

    /// Get QUIC certificate configuration
    public func getQuicCertificateConfig() throws -> QuicCertificateConfig {
        let nodeId = getNodeId()

        guard let nodeCert = issuedCertificates[nodeId] else {
            throw KeyError.certificateNotFound("Node certificate not found")
        }

        // Use the SecKey directly, like the POC does
        guard let secKey = certificateSecKeys[nodeId] else {
            throw KeyError.keyNotFound("Certificate SecKey not found - certificate may not have been generated properly")
        }

        // Prefer the CA that actually issued/was installed with this node certificate
        // installCertificate() sets certificateValidator to trust the provided CA
        let caCert = certificateValidator.getTrustedCACertificates().first ?? certificateAuthority.certificate

        // Convert certificates to DER format
        let nodeCertDer = nodeCert.toDER()
        let caCertDer = caCert.toDER()

        // Create certificate chain
        let certificateChain = [nodeCertDer, caCertDer]

        // For QUIC, we return the SecKey reference directly
        // The NetworkQuicTransporter will use this SecKey to create SecIdentity

        return QuicCertificateConfig(
            certificateChain: certificateChain,
            secKey: secKey,
            certificateValidator: certificateValidator
        )
    }

    /// Encrypt message for mobile using node's public key
    public func encryptMessageForMobile(message: Data, mobilePublicKey: Data) throws -> Data {
        try ECDHKeyPair.encryptECIES(data: message, recipientPublicKey: mobilePublicKey)
    }

    /// Decrypt message from mobile using node's private key
    public func decryptMessageFromMobile(encryptedMessage: Data) throws -> Data {
        guard let rootKey = userRootKey else {
            throw KeyError.keyNotFound("User root key not initialized")
        }

        return try rootKey.decryptECIES(encryptedData: encryptedMessage)
    }

    /// Encrypt local data using node storage key
    public func encryptLocalData(_ data: Data) throws -> Data {
        let storageKey = getStorageKey()
        return try encryptWithSymmetricKey(data, storageKey)
    }

    /// Decrypt local data using node storage key
    public func decryptLocalData(_ encryptedData: Data) throws -> Data {
        let storageKey = getStorageKey()
        return try decryptWithSymmetricKey(encryptedData, storageKey)
    }

    /// Get the node storage key for local encryption
    public func getStorageKey() -> Data {
        // Generate a deterministic storage key based on the root key
        guard let rootKey = userRootKey else {
            // Fallback to random key if root key not available
            var storageKey = Data(count: 32)
            storageKey.withUnsafeMutableBytes { bytes in
                _ = SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
            }
            return storageKey
        }

        // Derive storage key deterministically from root scalar using standardized labels
        let rootScalarBytes = rootKey.rawScalarBytes()
        return try! KeyDeriver.deriveStorageKey(masterScalar: rootScalarBytes, scope: "user-root", label: "storage-key")
    }

    /// Decrypt envelope-encrypted data using network key (NodeKeyManager compatibility)
    public func decryptEnvelopeData(_ envelopeData: EnvelopeEncryptedData) throws -> Data {
        try decryptWithNetwork(envelopeData: envelopeData)
    }

    // MARK: - State Management with Keychain

    /// Export all cryptographic material for Keychain persistence
    public func exportState() throws -> MobileKeyManagerState {
        // Serialize CA key pair
        let caKeyPairData = try serializeECDHKeyPair(certificateAuthority.getKeyPair())
        // Serialize CA certificate
        let caCertificateData = certificateAuthority.certificate.toDER()

        // Serialize user root key (if exists)
        var userRootKeyData: Data? = nil
        if let rootKey = userRootKey {
            userRootKeyData = try serializeECDHKeyPair(rootKey)
        }

        // Serialize user profile keys
        var serializedProfileKeys: [String: Data] = [:]
        for (pid, key) in userProfileKeys {
            serializedProfileKeys[pid] = try serializeECDHKeyPair(key)
        }

        // Serialize network data keys
        var serializedNetworkKeys: [String: Data] = [:]
        for (networkId, key) in networkDataKeys {
            serializedNetworkKeys[networkId] = try serializeECDHKeyPair(key)
        }

        // Serialize issued certificates
        var serializedCertificates: [String: Data] = [:]
        for (nodeId, cert) in issuedCertificates {
            serializedCertificates[nodeId] = cert.toDER()
        }

        // Serialize certificate key pairs
        var serializedCertificateKeyPairs: [String: Data] = [:]
        for (nodeId, keyPair) in certificateKeyPairs {
            serializedCertificateKeyPairs[nodeId] = try serializeECDHKeyPair(keyPair)
        }

        return MobileKeyManagerState(
            caKeyPair: caKeyPairData,
            caCertificate: caCertificateData,
            userRootKey: userRootKeyData,
            userProfileKeys: serializedProfileKeys,
            labelToPid: labelToPid,
            networkDataKeys: serializedNetworkKeys,
            networkPublicKeys: networkPublicKeys,
            issuedCertificates: serializedCertificates,
            certificateKeyLabels: certificateKeyLabels,
            certificateKeyPairs: serializedCertificateKeyPairs,
            certificateSecKeyLabels: certificateKeyLabels, // Use the same labels for SecKey retrieval
            serialCounter: serialCounter
        )
    }

    /// Save state to iOS/macOS Keychain
    public func saveToKeychain() throws {
        let state = try exportState()
        let stateData = try JSONEncoder().encode(state)

        // Create Keychain query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: stateData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        // Delete existing item if it exists
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyError.invalidOperation("Failed to save to Keychain: \(status)")
        }

        logger.info("Mobile Key Manager state saved to Keychain")
    }

    /// Load state from iOS/macOS Keychain
    public func loadFromKeychain() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let stateData = result as? Data
        else {
            throw KeyError.keyNotFound("No state found in Keychain")
        }

        let state = try JSONDecoder().decode(MobileKeyManagerState.self, from: stateData)
        try restoreFromState(state)

        logger.info("Mobile Key Manager state loaded from Keychain")
    }

    /// Restore a MobileKeyManager from a previously exported state
    public func restoreFromState(_ state: MobileKeyManagerState) throws {
        // Restore CA key pair and certificate
        let caKeyPair = try deserializeECDHKeyPair(state.caKeyPair)
        let caCertificate = try X509Certificate(derData: state.caCertificate)
        // Recreate certificate authority
        certificateAuthority = CertificateAuthority(keyPair: caKeyPair, certificate: caCertificate)
        // Recreate certificate validator
        certificateValidator = CertificateValidator(trustedCaCertificates: [caCertificate])
        // Restore user root key
        if let rootKeyData = state.userRootKey {
            userRootKey = try deserializeECDHKeyPair(rootKeyData)
        }
        // Restore user profile keys
        userProfileKeys.removeAll()
        for (pid, keyData) in state.userProfileKeys {
            userProfileKeys[pid] = try deserializeECDHKeyPair(keyData)
        }
        // Restore label to PID mapping
        labelToPid = state.labelToPid
        // Restore network data keys
        networkDataKeys.removeAll()
        for (networkId, keyData) in state.networkDataKeys {
            networkDataKeys[networkId] = try deserializeECDHKeyPair(keyData)
        }
        // Restore network public keys
        networkPublicKeys = state.networkPublicKeys
        // Restore issued certificates
        issuedCertificates.removeAll()
        for (nodeId, certData) in state.issuedCertificates {
            issuedCertificates[nodeId] = try X509Certificate(derData: certData)
        }
        // Restore certificate key labels
        certificateKeyLabels = state.certificateKeyLabels
        // Restore certificate key pairs
        certificateKeyPairs.removeAll()
        for (nodeId, keyData) in state.certificateKeyPairs {
            certificateKeyPairs[nodeId] = try deserializeECDHKeyPair(keyData)
        }
        // Restore certificate SecKeys from Keychain
        certificateSecKeys.removeAll()
        for (nodeId, keyLabel) in state.certificateSecKeyLabels {
            if let secKey = retrieveSecKeyFromKeychain(label: keyLabel) {
                certificateSecKeys[nodeId] = secKey
            }
        }
        // Restore serial counter
        serialCounter = state.serialCounter
        logger.info("Mobile Key Manager state restored successfully")
    }

    /// Check if state exists in Keychain
    public func hasKeychainState() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Clear state from Keychain
    public func clearKeychainState() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyError.invalidOperation("Failed to clear Keychain: \(status)")
        }

        logger.info("Mobile Key Manager state cleared from Keychain")
    }

    // MARK: - Private Helper Methods

    // Note: All HKDF derivations are centralized in KeyDeriver to ensure consistent salt/info strings.

    /// Serialize ECDHKeyPair to Data for storage
    private func serializeECDHKeyPair(_ keyPair: ECDHKeyPair) throws -> Data {
        // Store the raw scalar bytes (32 bytes)
        keyPair.rawScalarBytes()
    }

    /// Deserialize ECDHKeyPair from Data
    private func deserializeECDHKeyPair(_ data: Data) throws -> ECDHKeyPair {
        try ECDHKeyPair(rawRepresentation: data)
    }

    /// Extract raw 48-byte P-384 private scalar from SecKey external representation.
    /// Handles both RFC5915 ECPrivateKey and PKCS#8 PrivateKeyInfo wrapping ECPrivateKey.
    private func extractP384PrivateScalar(fromECPrivateKeyExternal data: Data) -> Data? {
        // Some keychain providers return raw big-endian scalar bytes
        if data.count >= 48 && data.count <= 64 && data[0] != 0x30 {
            return Data(data.suffix(48))
        }
        guard data.count > 0, data[0] == 0x30 else { return nil }
        var idx = 1
        func readLen() -> Int? {
            guard idx < data.count else { return nil }
            let first = Int(data[idx]); idx += 1
            if first < 0x80 { return first }
            let num = first & 0x7F
            guard num > 0, idx + num <= data.count else { return nil }
            var val = 0
            for _ in 0..<num { val = (val << 8) | Int(data[idx]); idx += 1 }
            return val
        }
        func readTLV() -> (UInt8, Data)? {
            guard idx < data.count else { return nil }
            let tag = data[idx]; idx += 1
            guard let length = readLen(), idx + length <= data.count else { return nil }
            let val = data[idx..<(idx + length)]
            idx += length
            return (tag, Data(val))
        }
        // Outer SEQUENCE
        _ = readLen()
        // Peek next TLV
        let savedIdx = idx
        guard let (tag1, v1) = readTLV(), tag1 == 0x02 else { return nil }
        // If version INTEGER is 0, likely PKCS#8: SEQ { INT 0, SEQ algId, OCTET STRING privateKey }
        if v1.count == 1, v1[0] == 0x00 {
            // algId
            guard let (algTag, _) = readTLV(), algTag == 0x30 else { return nil }
            // privateKey OCTET STRING which contains ECPrivateKey DER
            guard let (octTag, octVal) = readTLV(), octTag == 0x04 else { return nil }
            // The octet itself may be the ECPrivateKey SEQUENCE
            guard octVal.count > 0, octVal[0] == 0x30 else { return nil }
            // Parse ECPrivateKey sequence to get scalar
            var jdx = 1
            func rdLen(_ buf: Data, _ pos: inout Int) -> Int? {
                guard pos < buf.count else { return nil }
                let first = Int(buf[pos]); pos += 1
                if first < 0x80 { return first }
                let num = first & 0x7F
                guard num > 0, pos + num <= buf.count else { return nil }
                var val = 0
                for _ in 0..<num { val = (val << 8) | Int(buf[pos]); pos += 1 }
                return val
            }
            _ = rdLen(octVal, &jdx)
            // INTEGER version
            guard jdx < octVal.count, octVal[jdx] == 0x02 else { return nil }
            jdx += 1; _ = rdLen(octVal, &jdx); jdx += 1
            // OCTET STRING privateKey
            guard jdx < octVal.count, octVal[jdx] == 0x04 else { return nil }
            jdx += 1
            guard let pl = rdLen(octVal, &jdx), jdx + pl <= octVal.count else { return nil }
            let scalar = octVal[jdx..<(jdx + pl)]
            return Data(scalar.count == 48 ? Data(scalar) : Data(scalar.suffix(48)))
        }
        // Otherwise, attempt RFC5915 ECPrivateKey directly (we consumed first INTEGER already)
        idx = savedIdx
        // Expect INTEGER version
        guard let (tVer, vVer) = readTLV(), tVer == 0x02 else { return nil }
        _ = vVer
        // OCTET STRING privateKey
        guard let (tOct, vOct) = readTLV(), tOct == 0x04 else { return nil }
        return Data(vOct.count == 48 ? vOct : Data(vOct.suffix(48)))
    }

    /// Retrieve a SecKey from Keychain by label
    private func retrieveSecKeyFromKeychain(label: String) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let secKey = result {
            return (secKey as! SecKey)
        }
        return nil
    }

    /// Parse string DN to X509 DistinguishedName (relaxed: supports OU/ST/L and ignores unknown attributes)
    private func parseDistinguishedName(_ dn: String) throws -> DistinguishedName {
        var components: [RelativeDistinguishedName] = []
        let parts = dn.components(separatedBy: ",")

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let keyValue = trimmed.components(separatedBy: "=")
            guard keyValue.count == 2 else {
                throw KeyError.invalidOperation("Invalid DN component: \(trimmed)")
            }

            let key = keyValue[0].trimmingCharacters(in: .whitespaces).uppercased()
            let value = keyValue[1].trimmingCharacters(in: .whitespaces)

            let attribute: RelativeDistinguishedName.Attribute? = switch key {
            case "CN":
                .init(type: .RDNAttributeType.commonName, utf8String: value)
            case "C":
                try .init(type: .RDNAttributeType.countryName, printableString: value)
            case "O":
                .init(type: .RDNAttributeType.organizationName, utf8String: value)
            case "OU":
                .init(type: .RDNAttributeType.organizationalUnitName, utf8String: value)
            case "ST":
                .init(type: .RDNAttributeType.stateOrProvinceName, utf8String: value)
            case "L":
                .init(type: .RDNAttributeType.localityName, utf8String: value)
            default:
                nil
            }

            if let attribute {
                components.append(RelativeDistinguishedName([attribute]))
            }
        }

        return DistinguishedName(components)
    }

    /// Build RFC5915 ECPrivateKey DER (P-384) from raw 48-byte scalar and public key (uncompressed SEC1)
    private func buildECPrivateKeyDER(privateScalar: Data, publicX963: Data) -> Data {
        precondition(privateScalar.count == 48, "P-384 scalar must be 48 bytes")
        precondition(publicX963.count == 97 && publicX963.first == 0x04, "P-384 uncompressed public key must be 97 bytes starting with 0x04")

        func derLength(_ n: Int) -> Data {
            if n < 0x80 { return Data([UInt8(n)]) }
            var bytes: [UInt8] = []
            var val = n
            while val > 0 {
                bytes.insert(UInt8(val & 0xFF), at: 0)
                val >>= 8
            }
            return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
        }

        func tlv(_ tag: UInt8, _ value: Data) -> Data {
            Data([tag]) + derLength(value.count) + value
        }

        // INTEGER 1
        let version = tlv(0x02, Data([0x01]))
        // OCTET STRING of private key scalar
        let privOctet = tlv(0x04, privateScalar)
        // parameters [0] EXPLICIT namedCurve OID for secp384r1 (1.3.132.0.34)
        let oidBytes = Data([0x2B, 0x81, 0x04, 0x00, 0x22])
        let oid = tlv(0x06, oidBytes)
        let params = tlv(0xA0, oid)
        // publicKey [1] EXPLICIT BIT STRING of uncompressed public key
        let pubBitString = tlv(0x03, Data([0x00]) + publicX963)
        let pub = tlv(0xA1, pubBitString)

        let seqValue = version + privOctet + params + pub
        let seq = tlv(0x30, seqValue)
        return seq
    }

    /// Build PKCS#8 PrivateKeyInfo wrapping an ECPrivateKey for P-384
    private func buildPKCS8ECPrivateKeyDER(privateScalar: Data, publicX963: Data) -> Data {
        precondition(privateScalar.count == 48, "P-384 scalar must be 48 bytes")
        precondition(publicX963.count == 97 && publicX963.first == 0x04, "P-384 uncompressed public key must be 97 bytes starting with 0x04")

        func derLength(_ n: Int) -> Data {
            if n < 0x80 { return Data([UInt8(n)]) }
            var bytes: [UInt8] = []
            var val = n
            while val > 0 {
                bytes.insert(UInt8(val & 0xFF), at: 0)
                val >>= 8
            }
            return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
        }

        func tlv(_ tag: UInt8, _ value: Data) -> Data {
            Data([tag]) + derLength(value.count) + value
        }

        // version INTEGER 0
        let version = tlv(0x02, Data([0x00]))

        // privateKeyAlgorithm = SEQUENCE { OID id-ecPublicKey, OID secp384r1 }
        let oidIdEcPublicKey = tlv(0x06, Data([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])) // 1.2.840.10045.2.1
        let oidSecp384r1 = tlv(0x06, Data([0x2B, 0x81, 0x04, 0x00, 0x22])) // 1.3.132.0.34
        let algId = tlv(0x30, oidIdEcPublicKey + oidSecp384r1)

        // privateKey OCTET STRING = ECPrivateKey DER (with public key inside)
        let ecPriv = buildECPrivateKeyDER(privateScalar: privateScalar, publicX963: publicX963)
        let privOctet = tlv(0x04, ecPriv)

        let seqValue = version + algId + privOctet
        let seq = tlv(0x30, seqValue)
        return seq
    }
}

/// Statistics about the mobile key manager
public struct MobileKeyManagerStatistics {
    public let issuedCertificatesCount: Int
    public let userProfileKeysCount: Int
    public let networkKeysCount: Int
    public let caCertificateSubject: String
}
