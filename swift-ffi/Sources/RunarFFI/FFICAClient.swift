import CRunarFFI
import Foundation
import SwiftCBOR

// MARK: - CA Client Implementation

@available(macOS 11.0, *)
public class CAClient {
    private let handle: UnsafeMutableRawPointer
    private let logger: Logger
    private let nodeKeys: UnsafeMutableRawPointer

    init(handle: UnsafeMutableRawPointer, logger: Logger, nodeKeys: UnsafeMutableRawPointer) {
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
    ///   - logger: Logger instance
    /// - Returns: New CA Client instance
    /// - Throws: FFIError if the operation fails
    public static func createWithConfig(
        config: CaClientConfig,
        nodeKeys: UnsafeMutableRawPointer,
        logger: Logger
    ) throws -> CAClient {
        var out: UnsafeMutableRawPointer?

        // Convert config to CBOR
        let configData = try CodableCBOREncoder().encode(config)

        let (_, err) = withRnError { errPtr in
            configData.withUnsafeBytes { raw in
                rn_transport_ca_client_new_with_config(
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    configData.count,
                    nodeKeys,
                    UnsafeMutableRawPointer(bitPattern: 1),
                    &out,
                    errPtr
                )
            }
        }
        if let error = err { throw error }

        guard let clientHandle = out else {
            throw FFIError.operationFailed("Failed to create CA Client handle")
        }

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
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
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
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            authenticatedAddr.withCString { cAuthenticatedAddr in
                request.withUnsafeBytes { requestRaw in
                    rn_transport_ca_client_renew(
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
