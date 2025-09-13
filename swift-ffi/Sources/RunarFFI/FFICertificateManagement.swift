import CRunarFFI
import Foundation

// MARK: - Secure CA Node Management Implementation

@available(macOS 11.0, *)
public class CANodeManager {
    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    // MARK: - CA Node Setup (Secure Architecture)

    /// Complete CA Node setup with internal private key management
    /// This function handles all CA creation and configuration internally in Rust
    /// - Parameters:
    ///   - caNode: CA Node handle
    ///   - rootCaSubject: Root CA subject name
    ///   - issuingCaSubject: Issuing CA subject name
    ///   - validityDays: Certificate validity period in days
    ///   - issuingCaSerial: Serial number for issuing CA
    ///   - eaPublicKeys: EA public keys (CBOR-encoded)
    ///   - networkId: Network identifier
    /// - Throws: FFIError if the operation fails
    public func setupComplete(
        caNode: UnsafeMutableRawPointer,
        rootCaSubject: String,
        issuingCaSubject: String,
        validityDays: UInt32,
        issuingCaSerial: UInt64,
        eaPublicKeys: Data,
        networkId: String
    ) throws {
        let (_, err) = withRnError { errPtr in
            rootCaSubject.withCString { cRootSubject in
                issuingCaSubject.withCString { cIssuingSubject in
                    eaPublicKeys.withUnsafeBytes { eaRaw in
                        networkId.withCString { cNetworkId in
                            rn_keys_ca_node_setup_complete(
                                caNode,
                                cRootSubject,
                                cIssuingSubject,
                                validityDays,
                                issuingCaSerial,
                                eaRaw.bindMemory(to: UInt8.self).baseAddress,
                                eaPublicKeys.count,
                                cNetworkId,
                                errPtr
                            )
                        }
                    }
                }
            }
        }
        if let error = err { throw error }
    }
}

// MARK: - EA Key Management (Secure Architecture)

@available(macOS 11.0, *)
public class EAKeyManager {
    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    /// Create EA key pair (private key stays internal)
    /// - Returns: EA key handle
    /// - Throws: FFIError if the operation fails
    public func createKeyPair() throws -> UnsafeMutableRawPointer {
        var out: UnsafeMutableRawPointer?

        let (_, err) = withRnError { errPtr in
            rn_keys_ca_create_ea_key_pair(&out, errPtr)
        }
        if let error = err { throw error }

        guard let eaKeyHandle = out else {
            throw FFIError.operationFailed("Failed to create EA key pair handle")
        }

        return eaKeyHandle
    }

    /// Get EA public key (only public key exposed)
    /// - Parameter eaKeyHandle: EA key handle
    /// - Returns: DER-encoded public key
    /// - Throws: FFIError if the operation fails
    public func getPublicKey(_ eaKeyHandle: UnsafeMutableRawPointer) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            rn_keys_ca_get_ea_public_key(eaKeyHandle, &out, &outLen, errPtr)
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Generate enrollment token (uses internal private key)
    /// - Parameters:
    ///   - eaKeyHandle: EA key handle
    ///   - tokenId: Token identifier
    ///   - networkId: Network identifier
    ///   - subject: Certificate subject
    ///   - validFrom: Token validity start time (Unix timestamp)
    ///   - validUntil: Token validity end time (Unix timestamp)
    ///   - nonce: Random nonce
    ///   - capabilities: Token capabilities
    /// - Returns: CBOR-encoded enrollment token
    /// - Throws: FFIError if the operation fails
    public func generateEnrollmentToken(
        eaKeyHandle: UnsafeMutableRawPointer,
        tokenId: String,
        networkId: String,
        subject: String,
        validFrom: UInt64,
        validUntil: UInt64,
        nonce: Data,
        capabilities: [String]
    ) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            tokenId.withCString { cTokenId in
                networkId.withCString { cNetworkId in
                    subject.withCString { cSubject in
                        nonce.withUnsafeBytes { nonceRaw in
                            // For now, use empty capabilities array - this will be implemented when the FFI function is available
                            let emptyCapabilities: [UnsafePointer<CChar>?] = []
                            
                            rn_keys_ca_generate_enrollment_token(
                                eaKeyHandle,
                                cTokenId,
                                cNetworkId,
                                cSubject,
                                validFrom,
                                validUntil,
                                nonceRaw.bindMemory(to: UInt8.self).baseAddress,
                                nonce.count,
                                emptyCapabilities,
                                capabilities.count,
                                &out,
                                &outLen,
                                errPtr
                            )
                        }
                    }
                }
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Free EA key pair
    /// - Parameter eaKeyHandle: EA key handle to free
    public static func free(_ eaKeyHandle: UnsafeMutableRawPointer) {
        rn_keys_ca_free_ea_key_pair(eaKeyHandle)
    }
}

// MARK: - Certificate Utilities (Public Data Only)

@available(macOS 11.0, *)
public class CertificateUtilities {
    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    /// Extract certificate SKI (Subject Key Identifier)
    /// - Parameter cert: DER-encoded certificate
    /// - Returns: SKI as hex string
    /// - Throws: FFIError if the operation fails
    public func extractSki(_ cert: Data) throws -> String {
        var out: UnsafeMutablePointer<CChar>?

        let (_, err) = withRnError { errPtr in
            cert.withUnsafeBytes { raw in
                rn_keys_certificate_extract_ski(raw.bindMemory(to: UInt8.self).baseAddress, cert.count, &out, errPtr)
            }
        }
        if let error = err { throw error }

        defer { if let outString = out { rn_string_free(outString) } }
        return out.map { String(cString: $0) } ?? ""
    }

    /// Get certificate serial number
    /// - Parameter cert: DER-encoded certificate
    /// - Returns: Serial number as hex string
    /// - Throws: FFIError if the operation fails
    public func getSerial(_ cert: Data) throws -> String {
        var out: UnsafeMutablePointer<CChar>?

        let (_, err) = withRnError { errPtr in
            cert.withUnsafeBytes { raw in
                rn_keys_certificate_get_serial(raw.bindMemory(to: UInt8.self).baseAddress, cert.count, &out, errPtr)
            }
        }
        if let error = err { throw error }

        defer { if let outString = out { rn_string_free(outString) } }
        return out.map { String(cString: $0) } ?? ""
    }
}

// MARK: - Legacy Support (Deprecated)

@available(macOS 11.0, *)
@available(*, deprecated, message: "Use CANodeManager.setupComplete() instead. This class will be removed in a future version.")
public class CertificateManager {
    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    /// Create Root CA certificate
    /// - Parameter subject: Certificate subject
    /// - Returns: CA handle for further operations
    /// - Throws: FFIError if the operation fails
    @available(*, deprecated, message: "Use CANodeManager.setupComplete() instead")
    public func createRootCA(subject: String) throws -> UnsafeMutableRawPointer {
        throw FFIError.operationFailed("This function has been removed. Use CANodeManager.setupComplete() instead.")
    }

    /// Create Issuing CA certificate (signed by Root CA)
    /// - Parameters:
    ///   - rootCA: Root CA handle
    ///   - subject: Certificate subject
    ///   - validityDays: Validity period in days
    ///   - serial: Serial number
    /// - Returns: Issuing CA handle
    /// - Throws: FFIError if the operation fails
    @available(*, deprecated, message: "Use CANodeManager.setupComplete() instead")
    public func createIssuingCA(
        rootCA: UnsafeMutableRawPointer,
        subject: String,
        validityDays: UInt32,
        serial: UInt64
    ) throws -> UnsafeMutableRawPointer {
        throw FFIError.operationFailed("This function has been removed. Use CANodeManager.setupComplete() instead.")
    }

    /// Get CA certificate DER bytes
    /// - Parameter caHandle: CA handle
    /// - Returns: DER-encoded certificate
    /// - Throws: FFIError if the operation fails
    @available(*, deprecated, message: "Use CANodeManager.setupComplete() instead")
    public func getCertificateDer(_ caHandle: UnsafeMutableRawPointer) throws -> Data {
        throw FFIError.operationFailed("This function has been removed. Use CANodeManager.setupComplete() instead.")
    }

    /// Get CA certificate subject
    /// - Parameter caHandle: CA handle
    /// - Returns: Certificate subject string
    /// - Throws: FFIError if the operation fails
    @available(*, deprecated, message: "Use CANodeManager.setupComplete() instead")
    public func getCertificateSubject(_ caHandle: UnsafeMutableRawPointer) throws -> String {
        throw FFIError.operationFailed("This function has been removed. Use CANodeManager.setupComplete() instead.")
    }

    /// Free CA resources
    /// - Parameter caHandle: CA handle to free
    @available(*, deprecated, message: "Use CANodeManager.setupComplete() instead")
    public static func free(_ caHandle: UnsafeMutableRawPointer) {
        // No-op for deprecated function
    }

    /// Extract certificate SKI (Subject Key Identifier)
    /// - Parameter cert: DER-encoded certificate
    /// - Returns: SKI as hex string
    /// - Throws: FFIError if the operation fails
    @available(*, deprecated, message: "Use CertificateUtilities.extractSki() instead")
    public func extractSki(_ cert: Data) throws -> String {
        let utilities = CertificateUtilities(logger: logger)
        return try utilities.extractSki(cert)
    }

    /// Get certificate serial number
    /// - Parameter cert: DER-encoded certificate
    /// - Returns: Serial number as hex string
    /// - Throws: FFIError if the operation fails
    @available(*, deprecated, message: "Use CertificateUtilities.getSerial() instead")
    public func getSerial(_ cert: Data) throws -> String {
        let utilities = CertificateUtilities(logger: logger)
        return try utilities.getSerial(cert)
    }
}

// MARK: - Enrollment Token Management (Deprecated)

/// Parameters for enrollment token generation
@available(*, deprecated, message: "Use EAKeyManager.generateEnrollmentToken() instead")
public struct EnrollmentTokenParams {
    public let eaKey: Data
    public let tokenId: String
    public let networkId: String
    public let subject: String
    public let notBefore: UInt64
    public let expiresAt: UInt64
    public let nonce: Data
    public let permissions: Data

    public init(
        eaKey: Data,
        tokenId: String,
        networkId: String,
        subject: String,
        notBefore: UInt64,
        expiresAt: UInt64,
        nonce: Data,
        permissions: Data
    ) {
        self.eaKey = eaKey
        self.tokenId = tokenId
        self.networkId = networkId
        self.subject = subject
        self.notBefore = notBefore
        self.expiresAt = expiresAt
        self.nonce = nonce
        self.permissions = permissions
    }
}

@available(macOS 11.0, *)
@available(*, deprecated, message: "Use EAKeyManager instead")
public class EnrollmentTokenManager {
    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    /// Generate enrollment token
    /// - Parameter params: Token generation parameters
    /// - Returns: CBOR-encoded enrollment token
    /// - Throws: FFIError if the operation fails
    @available(*, deprecated, message: "Use EAKeyManager.generateEnrollmentToken() instead")
    public func generateToken(params: EnrollmentTokenParams) throws -> Data {
        throw FFIError.operationFailed("This function has been removed. Use EAKeyManager.generateEnrollmentToken() instead.")
    }

    /// Validate enrollment token
    /// - Parameters:
    ///   - token: CBOR-encoded enrollment token
    ///   - eaPublicKey: Enrollment Authority public key (DER-encoded)
    /// - Returns: true if token is valid, false otherwise
    /// - Throws: FFIError if the operation fails
    @available(*, deprecated, message: "Use EAKeyManager.generateEnrollmentToken() instead")
    public func validateToken(_ token: Data, eaPublicKey: Data) throws -> Bool {
        throw FFIError.operationFailed("This function has been removed. Use EAKeyManager.generateEnrollmentToken() instead.")
    }
}