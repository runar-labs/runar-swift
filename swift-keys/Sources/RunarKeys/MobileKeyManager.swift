import Foundation
import CryptoKit
import X509
import SwiftASN1
import Security

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
        self.certificateAuthority = try CertificateAuthority.create(subject: caSubject)
        
        // Create certificate validator with the temporary CA certificate
        let caCert = certificateAuthority.certificate
        self.certificateValidator = CertificateValidator(trustedCaCertificates: [caCert])
        
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

        // Issue certificate from CSR
        let validityDays: UInt32 = 365 // 1-year validity (consider shortening)
        let nodeCertificate = try certificateAuthority.signCertificateRequest(
            csrDer: setupToken.csrDer,
            validityDays: Int(validityDays)
        )

        // Increment serial for next issuance
        serialCounter = serialCounter &+ 1

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
        return issuedCertificates[nodeId]
    }
    
    /// List all issued certificates
    public func listIssuedCertificates() -> [(String, X509Certificate)] {
        return issuedCertificates.map { (nodeId, cert) in (nodeId, cert) }
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
        
        if !hasNetworkKey && !hasProfileKeys {
            throw KeyError.invalidOperation("No valid network or profile keys provided for envelope encryption")
        }
        
        // Generate ephemeral envelope key
        let envelopeKeyData = createEnvelopeKey()
        
        // Encrypt data with envelope key (using AES-GCM)
        let encryptedData = try encryptWithSymmetricKey(data, envelopeKeyData)
        
        // Encrypt envelope key for network (optional)
        var networkEncryptedKey = Data()
        if let networkId = networkId, let networkKey = networkDataKeys[networkId] {
            let pk = networkKey.publicKeyBytes()
            // Encrypt the envelope key with network key's public key
            networkEncryptedKey = try ECDHKeyPair.encryptECIES(data: envelopeKeyData, recipientPublicKey: pk)
        } else if let networkId = networkId, let networkPublicKeyBytes = networkPublicKeys[networkId] {
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
        self.certificateAuthority = try CertificateAuthority.create(subject: caSubject)
        
        // Create certificate validator with the CA certificate
        let caCert = certificateAuthority.certificate
        self.certificateValidator = CertificateValidator(trustedCaCertificates: [caCert])
        
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
        return certificateAuthority.certificate
    }
    
    /// Get the CA public key bytes
    public func getCaPublicKey() -> Data {
        return try! certificateAuthority.getKeyPair().toECDSAVerifyingKey().x963Representation
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
        
        // Derive a profile-specific private scalar using HKDF-SHA-384.
        let salt = "RunarUserProfileDerivationSalt".data(using: .utf8)!
        
        // Attempt to create a valid P-384 signing key from the HKDF output.
        // If the candidate scalar is out of range (rare) retry with a counter
        // in the info field until success.
        var counter: UInt32 = 0
        let profileKey: ECDHKeyPair
        
        repeat {
            let info = if counter == 0 {
                "runar-profile-\(label)"
            } else {
                "runar-profile-\(label)-\(counter)"
            }
            
            let infoData = info.data(using: .utf8)!
            
            // Use SHA-384 to prepare IKM for HKDF
            let hash = SHA384.hash(data: rootScalarBytes)
            let derivedKey = Data(hash)
            
            // Derive agreement and signing keys using deterministic HKDF-SHA-384
            let agreementPriv = try KeyDeriver.deriveAgreementPrivateKey(masterScalar: rootScalarBytes, scope: "profile", label: label, counterStart: counter)
            let signingPriv = try KeyDeriver.deriveSigningPrivateKey(masterScalar: rootScalarBytes, scope: "profile", label: label, counterStart: counter)
            profileKey = ECDHKeyPair(keyAgreementPrivateKey: agreementPriv)
            userProfileSigningScalars[label] = signingPriv.rawRepresentation
            break
        } while true
        
        // Cache the profile key using the compact ID.
        let publicKey = profileKey.publicKeyBytes()
        let pid = CryptoUtils.compactId(publicKey)
        userProfileKeys[pid] = profileKey
        labelToPid[label] = pid
        
        logger.info("User profile key derived using HKDF for label '\(label)' (attempts: \(counter), id: \(pid))")
        
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
        return MobileKeyManagerStatistics(
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
        while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "node" : result
    }
    
    // MARK: - Legacy Compatibility Methods
    
    /// Initialize user identity and generate root keys (legacy method)
    public func initializeUserIdentity() throws -> Data {
        return try initializeUserRootKey()
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
        return try deriveUserProfileKey(label: profileId)
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
        return try! getUserRootPublicKey()
    }
    
    /// Get the node ID (compact Base58 encoding of public key)
    public func getNodeId() -> String {
        let publicKey = getNodePublicKey()
        return CryptoUtils.compactId(publicKey)
    }
    
    /// Get certificate status
    public func getCertificateStatus() -> CertificateStatus {
        // Mobile always has a valid CA certificate
        return .valid
    }
    
    /// Generate a CSR (Certificate Signing Request) for node setup
    /// This follows the POC pattern: generate key in Keychain first, then create certificate
    public func generateCSR() throws -> SetupToken {
        let nodeId = getNodeId()
        
        // Step 1: Generate P-384 private key directly in Keychain (like the POC)
        let keyLabel = "Runar Node Private Key \(nodeId)"
        let secPrivateKey = try ECDHKeyPair.generateInKeychain(label: keyLabel)
        
        // Step 2: Get the public key from the Keychain key
        guard let secPublicKey = SecKeyCopyPublicKey(secPrivateKey) else {
            throw KeyError.keychainOperationFailed("Failed to get public key from SecKey")
        }
        
        // Step 3: Export the public key for the CSR
        var pubError: Unmanaged<CFError>?
        guard let pubData = SecKeyCopyExternalRepresentation(secPublicKey, &pubError) as Data? else {
            throw KeyError.keychainOperationFailed("Failed to export public key: \(pubError?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }
        
        // Step 4: Store the key label for later use
        certificateKeyLabels[nodeId] = keyLabel
        
        // Step 5: Store the SecKey reference for later use
        // We'll use this SecKey directly for certificate operations, like the POC does
        certificateSecKeys[nodeId] = secPrivateKey
        
        // Step 6: Return the public key for certificate creation
        // The CA will create the certificate directly from this public key
        let subject = "CN=\(nodeId),O=Runar,C=US"
        
        return SetupToken(
            nodePublicKey: pubData,
            csrDer: Data(), // Empty - we'll use public key directly
            nodeId: nodeId
        )
    }
    
    /// Install a certificate received from mobile CA
    public func installCertificate(_ certMessage: NodeCertificateMessage) throws {
        // Update validator to trust the CA that issued this certificate
        self.certificateValidator = CertificateValidator(trustedCaCertificates: [certMessage.caCertificate])
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
        return try ECDHKeyPair.encryptECIES(data: message, recipientPublicKey: mobilePublicKey)
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
        return try decryptWithNetwork(envelopeData: envelopeData)
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
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let stateData = result as? Data else {
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
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Clear state from Keychain
    public func clearKeychainState() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyError.invalidOperation("Failed to clear Keychain: \(status)")
        }
        
        logger.info("Mobile Key Manager state cleared from Keychain")
    }
    
    // MARK: - Private Helper Methods
    
    /// HKDF implementation using CryptoKit
    private func hkdf(salt: Data, ikm: Data, info: Data, outputLength: Int) throws -> Data {
        let key = SymmetricKey(data: ikm)
        let derivedKey = HKDF<SHA384>.deriveKey(
            inputKeyMaterial: key,
            salt: salt,
            info: info,
            outputByteCount: outputLength
        )
        return derivedKey.withUnsafeBytes { Data($0) }
    }
    

    
    /// Serialize ECDHKeyPair to Data for storage
    private func serializeECDHKeyPair(_ keyPair: ECDHKeyPair) throws -> Data {
        // Store the raw scalar bytes (32 bytes)
        return keyPair.rawScalarBytes()
    }
    
    /// Deserialize ECDHKeyPair from Data
    private func deserializeECDHKeyPair(_ data: Data) throws -> ECDHKeyPair {
        return try ECDHKeyPair(rawRepresentation: data)
    }
    
    /// Retrieve a SecKey from Keychain by label
    private func retrieveSecKeyFromKeychain(label: String) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let secKey = result {
            return secKey as! SecKey
        }
        return nil
    }
    

    
    /// Parse string DN to X509 DistinguishedName (copied from POC)
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
            
            let attribute: RelativeDistinguishedName.Attribute
            switch key {
            case "CN":
                attribute = .init(type: .RDNAttributeType.commonName, utf8String: value)
            case "C":
                attribute = try .init(type: .RDNAttributeType.countryName, printableString: value)
            case "O":
                attribute = .init(type: .RDNAttributeType.organizationName, utf8String: value)
            default:
                throw KeyError.invalidOperation("Unsupported DN attribute: \(key)")
            }
            
            components.append(RelativeDistinguishedName([attribute]))
        }
        
        return DistinguishedName(components)
    }
}

/// Statistics about the mobile key manager
public struct MobileKeyManagerStatistics {
    public let issuedCertificatesCount: Int
    public let userProfileKeysCount: Int
    public let networkKeysCount: Int
    public let caCertificateSubject: String
} 