import CRunarFFI
import Foundation
import SwiftCBOR
import SwiftCommon

// MARK: - CA Server Implementation

@available(macOS 11.0, *)
public class CAServer {
    private let handle: UnsafeMutableRawPointer
    private let logger: Logger
    private var bootstrapAddr: String?
    private var authenticatedAddr: String?

    public init(handle: UnsafeMutableRawPointer, logger: Logger) {
        self.handle = handle
        self.logger = logger
    }

    deinit {
        rn_transport_ca_server_free(handle)
    }

    // MARK: - CA Server Management

    /// Create new CA Server
    /// - Parameters:
    ///   - config: CA Server configuration
    ///   - sharedCaNode: Shared CA Node handle
    /// - Returns: New CA Server instance
    /// - Throws: FFIError if the operation fails
    public static func create(
        config: CaServerConfig,
        sharedCaNode: UnsafeMutableRawPointer
    ) throws -> CAServer {
        var out: UnsafeMutableRawPointer?

        // Convert config to CBOR
        let configData = try CodableCBOREncoder().encode(config)

        let (_, err) = withRnError { errPtr in
            configData.withUnsafeBytes { raw in
                rn_transport_ca_server_new(
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    configData.count,
                    sharedCaNode,
                    &out,
                    errPtr
                )
            }
        }
        if let error = err { throw error }

        guard let serverHandle = out else {
            throw FFIError.operationFailed("Failed to create CA Server handle")
        }

        return CAServer(handle: serverHandle, logger: RunarLogger(component: .transporter))
    }

    /// Configure admin SKIs
    /// - Parameter adminSkis: CBOR-encoded admin SKIs
    /// - Throws: FFIError if the operation fails
    public func configureAdminSkis(_ adminSkis: Data) throws {
        let (_, err) = withRnError { errPtr in
            adminSkis.withUnsafeBytes { raw in
                rn_transport_ca_server_configure_admin_skis(
                    handle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    adminSkis.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
    }

    /// Start CA Server
    /// - Throws: FFIError if the operation fails
    public func start() throws {
        let (_, err) = withRnError { errPtr in
            rn_transport_ca_server_start(handle, errPtr)
        }
        if let error = err { throw error }
    }

    /// Stop CA Server
    /// - Throws: FFIError if the operation fails
    public func stop() throws {
        let (_, err) = withRnError { errPtr in
            rn_transport_ca_server_stop(handle, errPtr)
        }
        if let error = err { throw error }
    }

    // MARK: - Address Management

    /// Get bootstrap address
    /// - Returns: Bootstrap server address
    /// - Throws: FFIError if the operation fails
    public func getBootstrapAddr() throws -> String {
        var out: UnsafeMutablePointer<CChar>?

        let (_, err) = withRnError { errPtr in
            rn_transport_ca_server_get_bootstrap_addr(handle, &out, errPtr)
        }
        if let error = err { throw error }

        defer { if let outString = out { rn_string_free(outString) } }
        let address = out.map { String(cString: $0) } ?? ""
        bootstrapAddr = address
        return address
    }

    /// Get authenticated address
    /// - Returns: Authenticated server address
    /// - Throws: FFIError if the operation fails
    public func getAuthenticatedAddr() throws -> String {
        var out: UnsafeMutablePointer<CChar>?

        let (_, err) = withRnError { errPtr in
            rn_transport_ca_server_get_authenticated_addr(handle, &out, errPtr)
        }
        if let error = err { throw error }

        defer { if let outString = out { rn_string_free(outString) } }
        let address = out.map { String(cString: $0) } ?? ""
        authenticatedAddr = address
        return address
    }

    // MARK: - Convenience Properties

    /// Cached bootstrap address (call getBootstrapAddr() first)
    public var bootstrapAddress: String? {
        bootstrapAddr
    }

    /// Cached authenticated address (call getAuthenticatedAddr() first)
    public var authenticatedAddress: String? {
        authenticatedAddr
    }
}
