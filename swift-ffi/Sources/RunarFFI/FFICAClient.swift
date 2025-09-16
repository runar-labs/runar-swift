import CRunarFFI
import Foundation
import SwiftCBOR
import SwiftCommon

// MARK: - CA Client Implementation

@available(macOS 11.0, *)
public class CAClient {
    private let handle: UnsafeMutableRawPointer
    private let logger: RunarLogger
    private let nodeKeys: UnsafeMutableRawPointer

    public var rawHandle: UnsafeMutableRawPointer {
        handle
    }

    init(handle: UnsafeMutableRawPointer, logger: RunarLogger, nodeKeys: UnsafeMutableRawPointer) {
        self.handle = handle
        self.logger = logger
        self.nodeKeys = nodeKeys
    }

    deinit {
        rn_transport_ca_client_free(handle)
    }

    // MARK: - CA Client Management

    /// Create new CA Client with configuration
    /// - Parameters:
    ///   - config: CA Client configuration
    ///   - nodeKeys: Node keys handle
    /// - Returns: New CA Client instance
    /// - Throws: FFIError if the operation fails
    public static func createWithConfig(
        config: CaClientConfigAll,
        nodeKeys: UnsafeMutableRawPointer
    ) throws -> CAClient {
        let logger = RunarLogger(component: .transporter)
        logger.trace("Creating CA client with config: bootstrap=\(config.bootstrap_server), " +
            "authenticated=\(config.authenticated_server), network_id=\(config.network_id)")

        var out: UnsafeMutableRawPointer?

        // Convert config to CBOR
        let configData = try CodableCBOREncoder().encode(config)
        logger.debug("Config encoded to CBOR: \(configData.count) bytes")

        let (_, err) = withRnError { errPtr in
            configData.withUnsafeBytes { raw in
                rn_transport_ca_client_new_with_config(
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    configData.count,
                    nodeKeys,
                    &out,
                    errPtr
                )
            }
        }
        if let error = err {
            logger.error("Failed to create CA client: \(error)")
            throw error
        }

        guard let clientHandle = out else {
            logger.error("CA client creation failed: handle is nil")
            throw FFIError.operationFailed("Failed to create CA Client handle")
        }

        logger.debug("CA client created successfully with handle: \(clientHandle)")
        return CAClient(handle: clientHandle, logger: logger, nodeKeys: nodeKeys)
    }

    // MARK: - CA Client Operations

    /// Enroll with CA Server
    /// - Parameters:
    ///   - bootstrapAddr: Bootstrap server address
    ///   - request: CBOR-encoded enrollment request
    /// - Returns: CBOR-encoded enrollment response
    /// - Throws: FFIError if the operation fails
    public func enroll(bootstrapAddr: String, request: Data) throws -> Data {
        logger.trace("Starting enrollment with bootstrap address: \(bootstrapAddr), " +
            "request size: \(request.count) bytes")

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            bootstrapAddr.withCString { cBootstrapAddr in
                request.withUnsafeBytes { requestRaw in
                    rn_transport_ca_client_enroll(
                        handle,
                        cBootstrapAddr,
                        requestRaw.bindMemory(to: UInt8.self).baseAddress,
                        request.count,
                        &out,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
        if let error = err {
            logger.error("Enrollment failed: \(error)")
            throw error
        }

        guard let outPtr = out else {
            logger.error("Enrollment returned nil response")
            return Data()
        }
        let data = Data(bytes: outPtr, count: outLen)
        logger.debug("Enrollment successful: response size \(outLen) bytes")
        rn_free(outPtr, outLen)
        return data
    }

    /// Renew certificate with CA Server
    /// - Parameters:
    ///   - authenticatedAddr: Authenticated server address
    ///   - request: CBOR-encoded renewal request
    /// - Returns: CBOR-encoded renewal response
    /// - Throws: FFIError if the operation fails
    public func renew(authenticatedAddr: String, request: Data) throws -> Data {
        logger.trace("CAClient.renew called with authenticatedAddr: \(authenticatedAddr), request size: \(request.count) bytes")
        logger.trace("CAClient.renew handle: \(handle)")
        
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        logger.trace("CAClient.renew calling rn_transport_ca_client_renew with handle: \(handle)")
        let (result, err) = withRnError { errPtr in
            logger.trace("CAClient.renew inside withRnError closure, calling FFI function")
            authenticatedAddr.withCString { cAuthenticatedAddr in
                logger.trace("CAClient.renew authenticatedAddr converted to CString: \(String(cString: cAuthenticatedAddr))")
                request.withUnsafeBytes { requestRaw in
                    logger.trace("CAClient.renew request bytes prepared, calling rn_transport_ca_client_renew")
                    let ffiResult = rn_transport_ca_client_renew(
                        handle,
                        cAuthenticatedAddr,
                        requestRaw.bindMemory(to: UInt8.self).baseAddress,
                        request.count,
                        &out,
                        &outLen,
                        errPtr
                    )
                    logger.trace("CAClient.renew rn_transport_ca_client_renew returned: \(ffiResult)")
                    return ffiResult
                }
            }
        }
        
        logger.trace("CAClient.renew FFI call completed, result: \(result)")
        if let error = err { 
            logger.error("CAClient.renew FFI call failed: \(error)")
            throw error 
        }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Revoke certificate with CA Server
    /// - Parameters:
    ///   - authenticatedAddr: Authenticated server address
    ///   - request: CBOR-encoded revocation request
    /// - Returns: CBOR-encoded revocation response
    /// - Throws: FFIError if the operation fails
    public func revoke(authenticatedAddr: String, request: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            authenticatedAddr.withCString { cAuthenticatedAddr in
                request.withUnsafeBytes { requestRaw in
                    rn_transport_ca_client_revoke(
                        handle,
                        cAuthenticatedAddr,
                        requestRaw.bindMemory(to: UInt8.self).baseAddress,
                        request.count,
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

    /// Get certificate chain from CA Server
    /// - Parameters:
    ///   - bootstrapAddr: Bootstrap server address
    ///   - networkId: Network identifier
    /// - Returns: CBOR-encoded chain response
    /// - Throws: FFIError if the operation fails
    public func getChain(bootstrapAddr: String, networkId: String) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            bootstrapAddr.withCString { cBootstrapAddr in
                networkId.withCString { cNetworkId in
                    rn_transport_ca_client_get_chain(
                        handle,
                        cBootstrapAddr,
                        cNetworkId,
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

    /// Get certificate status from CA Server
    /// - Parameters:
    ///   - authenticatedAddr: Authenticated server address
    ///   - networkId: Network identifier
    /// - Returns: CBOR-encoded status response
    /// - Throws: FFIError if the operation fails
    public func getStatus(authenticatedAddr: String, networkId: String) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            authenticatedAddr.withCString { cAuthenticatedAddr in
                networkId.withCString { cNetworkId in
                    rn_transport_ca_client_get_status(
                        handle,
                        cAuthenticatedAddr,
                        cNetworkId,
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

    /// Get CRL from CA Server
    /// - Parameters:
    ///   - authenticatedAddr: Authenticated server address
    ///   - networkId: Network identifier
    /// - Returns: CBOR-encoded CRL response
    /// - Throws: FFIError if the operation fails
    public func getCrl(authenticatedAddr: String, networkId: String) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            authenticatedAddr.withCString { cAuthenticatedAddr in
                networkId.withCString { cNetworkId in
                    rn_transport_ca_client_get_crl(
                        handle,
                        cAuthenticatedAddr,
                        cNetworkId,
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
}

