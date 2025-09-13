import CRunarFFI
import Foundation

// MARK: - Certificate Management Implementation

@available(macOS 11.0, *)
public class CertificateManager {
    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    // MARK: - CA Certificate Creation

    /// Create Root CA certificate
    /// - Parameter subject: Certificate subject
    /// - Returns: CA handle for further operations
    /// - Throws: FFIError if the operation fails
    public func createRootCA(subject: String) throws -> UnsafeMutableRawPointer {
        var out: UnsafeMutableRawPointer?

        let (_, err) = withRnError { errPtr in
            subject.withCString { cSubject in
                rn_keys_ca_create_root_ca(cSubject, &out, errPtr)
            }
        }
        if let error = err { throw error }

        guard let caHandle = out else {
            throw FFIError.operationFailed("Failed to create Root CA handle")
        }

        return caHandle
    }

    /// Create Issuing CA certificate (signed by Root CA)
    /// - Parameters:
    ///   - rootCA: Root CA handle
    ///   - subject: Certificate subject
    ///   - validityDays: Validity period in days
    ///   - serial: Serial number
    /// - Returns: Issuing CA handle
    /// - Throws: FFIError if the operation fails
    public func createIssuingCA(
        rootCA: UnsafeMutableRawPointer,
        subject: String,
        validityDays: UInt32,
        serial: UInt64
    ) throws -> UnsafeMutableRawPointer {
        var out: UnsafeMutableRawPointer?

        let (_, err) = withRnError { errPtr in
            subject.withCString { cSubject in
                rn_keys_ca_create_issuing_ca(rootCA, cSubject, validityDays, serial, &out, errPtr)
            }
        }
        if let error = err { throw error }

        guard let issuingCAHandle = out else {
            throw FFIError.operationFailed("Failed to create Issuing CA handle")
        }

        return issuingCAHandle
    }

    /// Get CA certificate DER bytes
    /// - Parameter caHandle: CA handle
    /// - Returns: DER-encoded certificate
    /// - Throws: FFIError if the operation fails
    public func getCertificateDer(_ caHandle: UnsafeMutableRawPointer) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            rn_keys_ca_get_certificate_der(caHandle, &out, &outLen, errPtr)
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Get CA certificate subject
    /// - Parameter caHandle: CA handle
    /// - Returns: Certificate subject string
    /// - Throws: FFIError if the operation fails
    public func getCertificateSubject(_ caHandle: UnsafeMutableRawPointer) throws -> String {
        var out: UnsafeMutablePointer<CChar>?

        let (_, err) = withRnError { errPtr in
            rn_keys_ca_get_certificate_subject(caHandle, &out, errPtr)
        }
        if let error = err { throw error }

        defer { if let outString = out { rn_string_free(outString) } }
        return out.map { String(cString: $0) } ?? ""
    }

    /// Free CA resources
    /// - Parameter caHandle: CA handle to free
    public static func free(_ caHandle: UnsafeMutableRawPointer) {
        rn_keys_ca_free(caHandle)
    }

    // MARK: - Certificate Utilities

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

// MARK: - Enrollment Token Management

/// Parameters for enrollment token generation
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
    /// - Parameter params: Token generation parameters
    /// - Returns: CBOR-encoded enrollment token
    /// - Throws: FFIError if the operation fails
    public func generateToken(params: EnrollmentTokenParams) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            params.eaKey.withUnsafeBytes { keyRaw in
                params.tokenId.withCString { cTokenId in
                    params.networkId.withCString { cNetworkId in
                        params.subject.withCString { cSubject in
                            params.nonce.withUnsafeBytes { nonceRaw in
                                params.permissions.withUnsafeBytes { permRaw in
                                    rn_keys_enrollment_token_generate(
                                        keyRaw.bindMemory(to: UInt8.self).baseAddress,
                                        params.eaKey.count,
                                        cTokenId,
                                        cNetworkId,
                                        cSubject,
                                        params.notBefore,
                                        params.expiresAt,
                                        nonceRaw.bindMemory(to: UInt8.self).baseAddress,
                                        params.nonce.count,
                                        permRaw.bindMemory(to: UInt8.self).baseAddress,
                                        params.permissions.count,
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
    ///   - eaPublicKey: Enrollment Authority public key (DER-encoded)
    /// - Returns: true if token is valid, false otherwise
    /// - Throws: FFIError if the operation fails
    public func validateToken(_ token: Data, eaPublicKey: Data) throws -> Bool {
        var isValid: Int32 = 0

        let (_, err) = withRnError { errPtr in
            token.withUnsafeBytes { tokenRaw in
                eaPublicKey.withUnsafeBytes { keyRaw in
                    rn_keys_enrollment_token_validate(
                        tokenRaw.bindMemory(to: UInt8.self).baseAddress,
                        token.count,
                        keyRaw.bindMemory(to: UInt8.self).baseAddress,
                        eaPublicKey.count,
                        &isValid,
                        errPtr
                    )
                }
            }
        }
        if let error = err { throw error }

        return isValid != 0
    }
}
