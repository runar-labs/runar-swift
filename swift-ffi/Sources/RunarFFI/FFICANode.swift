import CRunarFFI
import Foundation

// MARK: - CA Node Implementation

@available(macOS 11.0, *)
public class CANode {
    private let handle: UnsafeMutableRawPointer
    private let logger: Logger

    init(handle: UnsafeMutableRawPointer, logger: Logger) {
        self.handle = handle
        self.logger = logger
    }

    deinit {
        rn_keys_ca_node_free(handle)
    }

    // MARK: - CA Node Management

    /// Create new CA Node
    /// - Parameter logger: Logger instance
    /// - Returns: New CA Node instance
    /// - Throws: FFIError if the operation fails
    public static func create(logger: Logger) throws -> CANode {
        var out: UnsafeMutableRawPointer?

        let (_, err) = withRnError { errPtr in
            rn_keys_ca_node_new(UnsafeMutableRawPointer(bitPattern: 1), &out, errPtr)
        }
        if let error = err { throw error }

        guard let caNodeHandle = out else {
            throw FFIError.operationFailed("Failed to create CA Node handle")
        }

        return CANode(handle: caNodeHandle, logger: logger)
    }

    /// Create shared CA Node reference for server usage
    /// - Returns: Shared CA Node handle
    /// - Throws: FFIError if the operation fails
    public func createShared() throws -> UnsafeMutableRawPointer {
        var out: UnsafeMutableRawPointer?

        let (_, err) = withRnError { errPtr in
            rn_keys_ca_node_create_shared(handle, &out, errPtr)
        }
        if let error = err { throw error }

        guard let sharedHandle = out else {
            throw FFIError.operationFailed("Failed to create shared CA Node handle")
        }

        return sharedHandle
    }

    /// Free shared CA Node reference
    /// - Parameter sharedHandle: Shared CA Node handle to free
    public static func freeShared(_ sharedHandle: UnsafeMutableRawPointer) {
        rn_keys_ca_node_free_shared(sharedHandle)
    }

    // MARK: - CA Node Configuration

    /// Complete CA Node setup with internal private key management (SECURE)
    /// This function handles all CA creation and configuration internally in Rust
    /// - Parameter params: CA Node setup parameters
    /// - Throws: FFIError if the operation fails
    public func setupComplete(params: CANodeManager.CANodeSetupParams) throws {
        let (_, err) = withRnError { errPtr in
            params.rootCaSubject.withCString { cRootSubject in
                params.issuingCaSubject.withCString { cIssuingSubject in
                    params.eaPublicKeys.withUnsafeBytes { eaRaw in
                        params.networkId.withCString { cNetworkId in
                            rn_keys_ca_node_setup_complete(
                                handle,
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

    /// Install issuing CA in CA Node (DEPRECATED - Use setupComplete instead)
    /// - Parameters:
    ///   - issuingCaKey: Issuing CA private key (CBOR-encoded)
    ///   - issuingCaCert: Issuing CA certificate (DER-encoded)
    ///   - rootCaCert: Root CA certificate (DER-encoded)
    ///   - eaPublicKeys: EA public keys (CBOR-encoded)
    ///   - networkId: Network identifier
    /// - Throws: FFIError if the operation fails
    @available(*, deprecated, message: "Use setupComplete() instead. This function has been removed for security reasons.")
    public func installIssuingCA(
        issuingCaKey _: Data,
        issuingCaCert _: Data,
        rootCaCert _: Data,
        eaPublicKeys _: Data,
        networkId _: String
    ) throws {
        throw FFIError.operationFailed("This function has been removed for security reasons. Use setupComplete() instead.")
    }

    /// Configure enrollment authority
    /// - Parameter eaPublicKeys: CBOR-encoded enrollment authority public keys
    /// - Throws: FFIError if the operation fails
    public func configureEnrollmentAuthority(_ eaPublicKeys: Data) throws {
        let (_, err) = withRnError { errPtr in
            eaPublicKeys.withUnsafeBytes { raw in
                rn_keys_ca_node_configure_enrollment_authority(
                    handle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    eaPublicKeys.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
    }

    /// Add admin SKI to CA Node
    /// - Parameter ski: Subject Key Identifier (SKI) as hex string
    /// - Throws: FFIError if the operation fails
    public func addAdminSki(_ ski: String) throws {
        let (_, err) = withRnError { errPtr in
            ski.withCString { cSki in
                rn_keys_ca_node_add_admin_ski(handle, cSki, errPtr)
            }
        }
        if let error = err { throw error }
    }

    /// Revoke enrollment token
    /// - Parameter tokenId: Token ID to revoke
    /// - Throws: FFIError if the operation fails
    public func revokeToken(_ tokenId: String) throws {
        let (_, err) = withRnError { errPtr in
            tokenId.withCString { cTokenId in
                rn_keys_ca_node_revoke_token(handle, cTokenId, errPtr)
            }
        }
        if let error = err { throw error }
    }

    // MARK: - CA Node Request Handling

    /// Handle enrollment request
    /// - Parameters:
    ///   - request: CBOR-encoded enrollment request
    ///   - remoteAddr: Remote address string
    /// - Returns: CBOR-encoded enrollment response
    /// - Throws: FFIError if the operation fails
    public func handleEnroll(request: Data, remoteAddr: String) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            request.withUnsafeBytes { requestRaw in
                remoteAddr.withCString { cRemoteAddr in
                    rn_keys_ca_node_handle_enroll(
                        handle,
                        requestRaw.bindMemory(to: UInt8.self).baseAddress,
                        request.count,
                        cRemoteAddr,
                        &out,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Handle renewal request
    /// - Parameters:
    ///   - request: CBOR-encoded renewal request
    ///   - peerCert: DER-encoded peer certificate
    /// - Returns: CBOR-encoded renewal response
    /// - Throws: FFIError if the operation fails
    public func handleRenew(request: Data, peerCert: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            request.withUnsafeBytes { requestRaw in
                peerCert.withUnsafeBytes { certRaw in
                    rn_keys_ca_node_handle_renew(
                        handle,
                        requestRaw.bindMemory(to: UInt8.self).baseAddress,
                        request.count,
                        certRaw.bindMemory(to: UInt8.self).baseAddress,
                        peerCert.count,
                        &out,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Handle revocation request
    /// - Parameters:
    ///   - request: CBOR-encoded revocation request
    ///   - adminSki: Admin SKI for authorization
    /// - Returns: CBOR-encoded revocation response
    /// - Throws: FFIError if the operation fails
    public func handleRevoke(request: Data, adminSki: String) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            request.withUnsafeBytes { requestRaw in
                adminSki.withCString { cAdminSki in
                    rn_keys_ca_node_handle_revoke(
                        handle,
                        requestRaw.bindMemory(to: UInt8.self).baseAddress,
                        request.count,
                        cAdminSki,
                        &out,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Handle chain request
    /// - Parameter networkId: Network identifier
    /// - Returns: CBOR-encoded chain response
    /// - Throws: FFIError if the operation fails
    public func handleChain(networkId: String) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            networkId.withCString { cNetworkId in
                rn_keys_ca_node_handle_chain(handle, cNetworkId, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Handle status request
    /// - Parameter networkId: Network identifier
    /// - Returns: CBOR-encoded status response
    /// - Throws: FFIError if the operation fails
    public func handleStatus(networkId: String) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            networkId.withCString { cNetworkId in
                rn_keys_ca_node_handle_status(handle, cNetworkId, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Handle CRL request
    /// - Parameter networkId: Network identifier
    /// - Returns: CBOR-encoded CRL response
    /// - Throws: FFIError if the operation fails
    public func handleCrl(networkId: String) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            networkId.withCString { cNetworkId in
                rn_keys_ca_node_handle_crl(handle, cNetworkId, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Generate CRL-lite
    /// - Returns: CBOR-encoded CRL-lite data
    /// - Throws: FFIError if the operation fails
    public func generateCrlLite() throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            rn_keys_ca_node_generate_crl_lite(handle, &out, &outLen, errPtr)
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }
}
