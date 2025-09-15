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

    /// Parameters for CA Node setup
    public struct CANodeSetupParams {
        public let caNode: UnsafeMutableRawPointer
        public let rootCaSubject: String
        public let issuingCaSubject: String
        public let validityDays: UInt32
        public let issuingCaSerial: UInt64
        public let eaPublicKeys: Data
        public let networkId: String

        public init(
            caNode: UnsafeMutableRawPointer,
            rootCaSubject: String,
            issuingCaSubject: String,
            validityDays: UInt32,
            issuingCaSerial: UInt64,
            eaPublicKeys: Data,
            networkId: String
        ) {
            self.caNode = caNode
            self.rootCaSubject = rootCaSubject
            self.issuingCaSubject = issuingCaSubject
            self.validityDays = validityDays
            self.issuingCaSerial = issuingCaSerial
            self.eaPublicKeys = eaPublicKeys
            self.networkId = networkId
        }
    }

    /// Complete CA Node setup with internal private key management
    /// This function handles all CA creation and configuration internally in Rust
    /// - Parameter params: CA Node setup parameters
    /// - Throws: FFIError if the operation fails
    public func setupComplete(params: CANodeSetupParams) throws {
        let (_, err) = withRnError { errPtr in
            params.rootCaSubject.withCString { cRootSubject in
                params.issuingCaSubject.withCString { cIssuingSubject in
                    params.eaPublicKeys.withUnsafeBytes { eaRaw in
                        params.networkId.withCString { cNetworkId in
                            rn_keys_ca_node_setup_complete(
                                params.caNode,
                                cRootSubject,
                                cIssuingSubject,
                                params.validityDays,
                                params.issuingCaSerial,
                                eaRaw.bindMemory(to: UInt8.self).baseAddress,
                                params.eaPublicKeys.count,
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

    /// Parameters for enrollment token generation
    public struct EnrollmentTokenParams {
        public let eaKeyHandle: UnsafeMutableRawPointer
        public let tokenId: String
        public let networkId: String
        public let subject: String
        public let validFrom: UInt64
        public let validUntil: UInt64
        public let nonce: Data
        public let capabilities: [String]

        public init(
            eaKeyHandle: UnsafeMutableRawPointer,
            tokenId: String,
            networkId: String,
            subject: String,
            validFrom: UInt64,
            validUntil: UInt64,
            nonce: Data,
            capabilities: [String]
        ) {
            self.eaKeyHandle = eaKeyHandle
            self.tokenId = tokenId
            self.networkId = networkId
            self.subject = subject
            self.validFrom = validFrom
            self.validUntil = validUntil
            self.nonce = nonce
            self.capabilities = capabilities
        }
    }

    /// Generate enrollment token (uses internal private key)
    /// - Parameter params: Enrollment token generation parameters
    /// - Returns: CBOR-encoded enrollment token
    /// - Throws: FFIError if the operation fails
    public func generateEnrollmentToken(params: EnrollmentTokenParams) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            params.tokenId.withCString { cTokenId in
                params.networkId.withCString { cNetworkId in
                    params.subject.withCString { cSubject in
                        params.nonce.withUnsafeBytes { nonceRaw in
                            // Convert capabilities to C string array with proper lifetime management
                            let capabilitiesCStrings = params.capabilities.map { capability in
                                capability.withCString { cString in
                                    let length = strlen(cString) + 1
                                    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: length)
                                    buffer.initialize(from: cString, count: length)
                                    return buffer
                                }
                            }
                            defer {
                                for cString in capabilitiesCStrings {
                                    cString.deallocate()
                                }
                            }
                            
                            let capabilitiesPtrs = capabilitiesCStrings.map { UnsafePointer<CChar>($0) as UnsafePointer<CChar>? }
                            
                            rn_keys_ca_generate_enrollment_token(
                                params.eaKeyHandle,
                                cTokenId,
                                cNetworkId,
                                cSubject,
                                params.validFrom,
                                params.validUntil,
                                nonceRaw.bindMemory(to: UInt8.self).baseAddress,
                                params.nonce.count,
                                capabilitiesPtrs,
                                params.capabilities.count,
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
    public func createRootCA(subject _: String) throws -> UnsafeMutableRawPointer {
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
        rootCA _: UnsafeMutableRawPointer,
        subject _: String,
        validityDays _: UInt32,
        serial _: UInt64
    ) throws -> UnsafeMutableRawPointer {
        throw FFIError.operationFailed("This function has been removed. Use CANodeManager.setupComplete() instead.")
    }

    /// Get CA certificate DER bytes
    /// - Parameter caHandle: CA handle
    /// - Returns: DER-encoded certificate
    /// - Throws: FFIError if the operation fails
    public func getCertificateDer(_ caHandle: UnsafeMutableRawPointer) throws -> Data {
        var outCert: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            rn_keys_ca_get_certificate_der(caHandle, &outCert, &outLen, errPtr)
        }
        if let error = err { throw error }

        guard let certPtr = outCert else { return Data() }
        let data = Data(bytes: certPtr, count: outLen)
        rn_free(certPtr, outLen)
        return data
    }

    /// Get CA certificate subject
    /// - Parameter caHandle: CA handle
    /// - Returns: Certificate subject string
    /// - Throws: FFIError if the operation fails
    public func getCertificateSubject(_ caHandle: UnsafeMutableRawPointer) throws -> String {
        var outSubject: UnsafeMutablePointer<CChar>?

        let (_, err) = withRnError { errPtr in
            rn_keys_ca_get_certificate_subject(caHandle, &outSubject, errPtr)
        }
        if let error = err { throw error }

        guard let subjectPtr = outSubject else { return "" }
        let subject = String(cString: subjectPtr)
        rn_string_free(subjectPtr)
        return subject
    }

    /// Free CA resources
    /// - Parameter caHandle: CA handle to free
    @available(*, deprecated, message: "Use CANodeManager.setupComplete() instead")
    public static func free(_: UnsafeMutableRawPointer) {
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
public class EnrollmentTokenManager {
    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    /// Generate enrollment token
    /// - Parameters:
    ///   - eaKey: EA public key data
    ///   - tokenId: Unique token identifier
    ///   - networkId: Network identifier
    ///   - subject: Token subject
    ///   - notBefore: Token validity start time (Unix timestamp)
    ///   - expiresAt: Token expiration time (Unix timestamp)
    ///   - nonce: Random nonce data
    ///   - permissions: Token permissions data
    /// - Returns: CBOR-encoded enrollment token
    /// - Throws: FFIError if the operation fails
    public func generateToken(
        eaKey: Data,
        tokenId: String,
        networkId: String,
        subject: String,
        notBefore: UInt64,
        expiresAt: UInt64,
        nonce: Data,
        permissions: Data
    ) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            eaKey.withUnsafeBytes { eaKeyRaw in
                nonce.withUnsafeBytes { nonceRaw in
                    permissions.withUnsafeBytes { permissionsRaw in
                        tokenId.withCString { cTokenId in
                            networkId.withCString { cNetworkId in
                                subject.withCString { cSubject in
                                    rn_keys_enrollment_token_generate(
                                        eaKeyRaw.bindMemory(to: UInt8.self).baseAddress,
                                        eaKey.count,
                                        cTokenId,
                                        cNetworkId,
                                        cSubject,
                                        notBefore,
                                        expiresAt,
                                        nonceRaw.bindMemory(to: UInt8.self).baseAddress,
                                        nonce.count,
                                        permissionsRaw.bindMemory(to: UInt8.self).baseAddress,
                                        permissions.count,
                                        &out,
                                        &outLen,
                                        errPtr
                                    )
                                }
                            }
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

    /// Validate enrollment token
    /// - Parameters:
    ///   - token: CBOR-encoded enrollment token
    ///   - eaPublicKey: EA public key for validation
    /// - Returns: true if token is valid, false otherwise
    /// - Throws: FFIError if the operation fails
    public func validateToken(token: Data, eaPublicKey: Data) throws -> Bool {
        var outValid: Int32 = 0

        let (_, err) = withRnError { errPtr in
            token.withUnsafeBytes { tokenRaw in
                eaPublicKey.withUnsafeBytes { keyRaw in
                    rn_keys_enrollment_token_validate(
                        tokenRaw.bindMemory(to: UInt8.self).baseAddress,
                        token.count,
                        keyRaw.bindMemory(to: UInt8.self).baseAddress,
                        eaPublicKey.count,
                        &outValid,
                        errPtr
                    )
                }
            }
        }
        if let error = err { throw error }

        return outValid != 0
    }
}
