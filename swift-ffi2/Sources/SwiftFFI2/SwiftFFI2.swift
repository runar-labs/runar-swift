import Foundation
import SwiftCBOR
import SwiftCommon
import CRunarFFI

// MARK: - FFI Error Types

public enum FFIError: Error, LocalizedError {
    case operationFailed(String)
    case invalidParameter(String)
    case memoryError(String)
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        case .invalidParameter(let message):
            return "Invalid parameter: \(message)"
        case .memoryError(let message):
            return "Memory error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - FFI Logger

public class FFILogger {
    public enum LogLevel: Int32, CaseIterable {
        case trace = 0
        case debug = 1
        case info = 2
        case warn = 3
        case error = 4
        
        public var stringValue: String {
            switch self {
            case .trace: return "TRACE"
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warn: return "WARN"
            case .error: return "ERROR"
            }
        }
    }
    
    /// Set the global log level for the Rust FFI logger
    /// - Parameter level: The log level to set
    public static func setLogLevel(_ level: LogLevel) {
        rn_set_log_level(level.rawValue)
    }
    
    /// Set the node ID for the Rust FFI logger context
    /// - Parameter nodeId: The node ID to set for logging context
    /// - Throws: FFIError if the operation fails
    public static func setLoggerNodeId(_ nodeId: String) throws {
        let (result, error) = withRnError { errPtr in
            nodeId.withCString { cNodeId in
                rn_set_logger_node_id(cNodeId, errPtr)
            }
        }
        
        if result != 0 {
            throw error ?? FFIError.operationFailed("Failed to set logger node ID")
        }
    }
    
    /// Log a message using the Rust FFI logger
    /// - Parameters:
    ///   - level: The log level
    ///   - message: The message to log
    /// - Note: This is a convenience method that integrates with SwiftCommon's RunarLogger
    public static func log(_ level: LogLevel, _ message: String) {
        // The actual logging is handled by the Rust side through the log level setting
        // This method is provided for API consistency but relies on SwiftCommon's RunarLogger
        // in the calling code for actual output
    }
}

// MARK: - FFI Helper Functions

@inline(__always)
private func buildError(from err: RNAPIRnError) -> Error {
    if let msgPtr = err.message {
        let message = String(cString: msgPtr)
        rn_string_free(msgPtr)
        return FFIError.operationFailed(message)
    }
    return FFIError.operationFailed("Unknown FFI error")
}

@inline(__always)
func withRnErrorCode(_ body: (UnsafeMutablePointer<RNAPIRnError>) -> Int32) -> (Int32, Error?) {
    var err = RNAPIRnError(code: 0, message: nil)
    let code = withUnsafeMutablePointer(to: &err) { errPtr in
        body(errPtr)
    }
    if code != 0 { return (code, buildError(from: err)) }
    return (code, nil)
}

@inline(__always)
public func withRnError(_ body: (UnsafeMutablePointer<RNAPIRnError>) -> Int32) -> (Int32, Error?) {
    return withRnErrorCode(body)
}

// MARK: - Copy-and-free helpers for FFI outputs

@inline(__always)
private func copyBytesAndFree(_ pointer: UnsafeMutablePointer<UInt8>?, _ length: Int) throws -> Data {
    guard let pointer = pointer, length > 0 else {
        throw FFIError.memoryError("Invalid FFI buffer")
    }
    let data = Data(bytes: pointer, count: length)
    rn_free(pointer, length)
    return data
}

@inline(__always)
private func copyCStringAndFree(_ pointer: UnsafeMutablePointer<CChar>?) throws -> String {
    guard let pointer = pointer else { throw FFIError.memoryError("Invalid FFI string") }
    let string = String(cString: pointer)
    rn_string_free(pointer)
    return string
}

// MARK: - Data Extensions

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}

// MARK: - CBOR Data Structures

// These are the data structures used by the tests
// They need to match the Rust FFI interface

public struct EnrollmentToken: Codable {
    public let body: EnrollmentTokenBody
    public let signature: Data
    public let signer_id: String
    
    enum CodingKeys: String, CodingKey {
        case body
        case signature
        case signer_id
    }

    public init(body: EnrollmentTokenBody, signature: Data, signer_id: String) {
        self.body = body
        self.signature = signature
        self.signer_id = signer_id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        body = try container.decode(EnrollmentTokenBody.self, forKey: .body)
        // Support both CBOR byte string and array<u8>
        if let sigBytes = try? container.decode([UInt8].self, forKey: .signature) {
            signature = Data(sigBytes)
        } else {
            signature = try container.decode(Data.self, forKey: .signature)
        }
        signer_id = try container.decode(String.self, forKey: .signer_id)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(body, forKey: .body)
        try container.encode(Array(signature), forKey: .signature)
        try container.encode(signer_id, forKey: .signer_id)
    }
}

public struct EnrollmentTokenBody: Codable {
    public let token_id: String
    public let network_id: String
    public let subject_hint: String?
    public let not_before: UInt64
    public let expires_at: UInt64
    public let nonce: Data
    public let permissions: [String]
    
    enum CodingKeys: String, CodingKey {
        case token_id
        case network_id
        case subject_hint
        case not_before
        case expires_at
        case nonce
        case permissions
    }

    public init(token_id: String, network_id: String, subject_hint: String?, not_before: UInt64, expires_at: UInt64, nonce: Data, permissions: [String]) {
        self.token_id = token_id
        self.network_id = network_id
        self.subject_hint = subject_hint
        self.not_before = not_before
        self.expires_at = expires_at
        self.nonce = nonce
        self.permissions = permissions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token_id = try container.decode(String.self, forKey: .token_id)
        network_id = try container.decode(String.self, forKey: .network_id)
        subject_hint = try container.decodeIfPresent(String.self, forKey: .subject_hint)
        not_before = try container.decode(UInt64.self, forKey: .not_before)
        expires_at = try container.decode(UInt64.self, forKey: .expires_at)
        if let nonceBytes = try? container.decode([UInt8].self, forKey: .nonce) {
            nonce = Data(nonceBytes)
        } else {
            nonce = try container.decode(Data.self, forKey: .nonce)
        }
        permissions = try container.decode([String].self, forKey: .permissions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token_id, forKey: .token_id)
        try container.encode(network_id, forKey: .network_id)
        try container.encodeIfPresent(subject_hint, forKey: .subject_hint)
        try container.encode(not_before, forKey: .not_before)
        try container.encode(expires_at, forKey: .expires_at)
        try container.encode(Array(nonce), forKey: .nonce)
        try container.encode(permissions, forKey: .permissions)
    }
}

public struct SetupToken: Codable {
    public let node_id: String
    public let node_public_key: Data
    public let node_agreement_public_key: Data
    public let csr_der: Data
    
    enum CodingKeys: String, CodingKey {
        case node_id
        case node_public_key
        case node_agreement_public_key
        case csr_der
    }

    public init(node_id: String, node_public_key: Data, node_agreement_public_key: Data, csr_der: Data) {
        self.node_id = node_id
        self.node_public_key = node_public_key
        self.node_agreement_public_key = node_agreement_public_key
        self.csr_der = csr_der
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        node_id = try container.decode(String.self, forKey: .node_id)
        if let pkBytes = try? container.decode([UInt8].self, forKey: .node_public_key) {
            node_public_key = Data(pkBytes)
        } else {
            node_public_key = try container.decode(Data.self, forKey: .node_public_key)
        }
        if let agreeBytes = try? container.decode([UInt8].self, forKey: .node_agreement_public_key) {
            node_agreement_public_key = Data(agreeBytes)
        } else {
            node_agreement_public_key = try container.decode(Data.self, forKey: .node_agreement_public_key)
        }
        if let csrBytes = try? container.decode([UInt8].self, forKey: .csr_der) {
            csr_der = Data(csrBytes)
        } else {
            csr_der = try container.decode(Data.self, forKey: .csr_der)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(node_id, forKey: .node_id)
        try container.encode(Array(node_public_key), forKey: .node_public_key)
        try container.encode(Array(node_agreement_public_key), forKey: .node_agreement_public_key)
        try container.encode(Array(csr_der), forKey: .csr_der)
    }
}

public struct CsrEnrollRequest: Codable {
    public let network_id: String
    public let csr_der: Data
    public let enrollment_token: EnrollmentToken
    
    enum CodingKeys: String, CodingKey {
        case network_id
        case csr_der
        case enrollment_token
    }

    public init(network_id: String, csr_der: Data, enrollment_token: EnrollmentToken) {
        self.network_id = network_id
        self.csr_der = csr_der
        self.enrollment_token = enrollment_token
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network_id = try container.decode(String.self, forKey: .network_id)
        if let csrBytes = try? container.decode([UInt8].self, forKey: .csr_der) {
            csr_der = Data(csrBytes)
        } else {
            csr_der = try container.decode(Data.self, forKey: .csr_der)
        }
        enrollment_token = try container.decode(EnrollmentToken.self, forKey: .enrollment_token)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network_id, forKey: .network_id)
        try container.encode(Array(csr_der), forKey: .csr_der)
        try container.encode(enrollment_token, forKey: .enrollment_token)
    }
}

public struct RenewRequest: Codable {
    public let network_id: String
    public let csr_der: Data
    
    enum CodingKeys: String, CodingKey {
        case network_id
        case csr_der
    }

    public init(network_id: String, csr_der: Data) {
        self.network_id = network_id
        self.csr_der = csr_der
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network_id = try container.decode(String.self, forKey: .network_id)
        if let csrBytes = try? container.decode([UInt8].self, forKey: .csr_der) {
            csr_der = Data(csrBytes)
        } else {
            csr_der = try container.decode(Data.self, forKey: .csr_der)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network_id, forKey: .network_id)
        try container.encode(Array(csr_der), forKey: .csr_der)
    }
}

public struct RevokeRequest: Codable {
    public let network_id: String
    public let certificate_serial: [UInt8]
    public let reason: String
    
    enum CodingKeys: String, CodingKey {
        case network_id
        case certificate_serial
        case reason
    }
}

public struct CustomCaServerConfig: Codable {
    public let bootstrap_bind: String
    public let authenticated_bind: String
    public let network_id: String
    public let rate_limit_per_minute: Int
    public let rate_limit_per_hour: Int
    
    enum CodingKeys: String, CodingKey {
        case bootstrap_bind
        case authenticated_bind
        case network_id
        case rate_limit_per_minute
        case rate_limit_per_hour
    }
}

public struct CaClientConfigAll: Codable {
    public let bootstrap_server: String
    public let authenticated_server: String
    public let network_id: String
    public let request_timeout_seconds: UInt32
    public let max_retries: UInt32
    public let root_ca_der: Data
    public let issuing_ca_der: Data

    public init(bootstrap_server: String,
                authenticated_server: String,
                network_id: String,
                request_timeout_seconds: UInt32,
                max_retries: UInt32,
                root_ca_der: Data,
                issuing_ca_der: Data) {
        self.bootstrap_server = bootstrap_server
        self.authenticated_server = authenticated_server
        self.network_id = network_id
        self.request_timeout_seconds = request_timeout_seconds
        self.max_retries = max_retries
        self.root_ca_der = root_ca_der
        self.issuing_ca_der = issuing_ca_der
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bootstrap_server = try container.decode(String.self, forKey: .bootstrap_server)
        authenticated_server = try container.decode(String.self, forKey: .authenticated_server)
        network_id = try container.decode(String.self, forKey: .network_id)
        request_timeout_seconds = try container.decode(UInt32.self, forKey: .request_timeout_seconds)
        max_retries = try container.decode(UInt32.self, forKey: .max_retries)
        if let rootBytes = try? container.decode([UInt8].self, forKey: .root_ca_der) {
            root_ca_der = Data(rootBytes)
        } else {
            root_ca_der = try container.decode(Data.self, forKey: .root_ca_der)
        }
        if let issuingBytes = try? container.decode([UInt8].self, forKey: .issuing_ca_der) {
            issuing_ca_der = Data(issuingBytes)
        } else {
            issuing_ca_der = try container.decode(Data.self, forKey: .issuing_ca_der)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bootstrap_server, forKey: .bootstrap_server)
        try container.encode(authenticated_server, forKey: .authenticated_server)
        try container.encode(network_id, forKey: .network_id)
        try container.encode(request_timeout_seconds, forKey: .request_timeout_seconds)
        try container.encode(max_retries, forKey: .max_retries)
        try container.encode(Array(root_ca_der), forKey: .root_ca_der)
        try container.encode(Array(issuing_ca_der), forKey: .issuing_ca_der)
    }

    enum CodingKeys: String, CodingKey {
        case bootstrap_server
        case authenticated_server
        case network_id
        case request_timeout_seconds
        case max_retries
        case root_ca_der
        case issuing_ca_der
    }
}

// MARK: - Public Server Config to match test usage

public struct CaServerConfig {
    public let bootstrapBind: String
    public let authenticatedBind: String
    public let networkId: String
    public let rateLimitPerMinute: Int
    public let rateLimitPerHour: Int
    
    public init(bootstrapBind: String,
                authenticatedBind: String,
                networkId: String,
                rateLimitPerMinute: Int,
                rateLimitPerHour: Int) {
        self.bootstrapBind = bootstrapBind
        self.authenticatedBind = authenticatedBind
        self.networkId = networkId
        self.rateLimitPerMinute = rateLimitPerMinute
        self.rateLimitPerHour = rateLimitPerHour
    }
}

// MARK: - Logger bridge (use SwiftCommon's RunarLogger)
// Test creates RunarLogger(component: .custom). Type comes from SwiftCommon.

public class EAKeyManager {
    public struct EnrollmentTokenParams {
        public let eaKeyHandle: UnsafeMutableRawPointer
        public let tokenId: String
        public let networkId: String
        public let subject: String
        public let validFrom: UInt64
        public let validUntil: UInt64
        public let nonce: Data
        public let capabilities: [String]
    }
    
    public init(logger: RunarLogger) {}
    
    public func createKeyPair() throws -> UnsafeMutableRawPointer {
        var handle: UnsafeMutableRawPointer?
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_ca_create_ea_key_pair(&handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0, let out = handle else {
            throw FFIError.operationFailed("Failed to create EA key pair")
        }
        return out
    }
    
    public func getPublicKey(_ handle: UnsafeMutableRawPointer) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_ca_get_ea_public_key(handle, &outPtr, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else {
            throw FFIError.operationFailed("Failed to get EA public key")
        }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    public func generateEnrollmentToken(params: EnrollmentTokenParams) throws -> Data {
        // Allocate stable C strings for capabilities
        let capabilityCStringPtrs: [UnsafeMutablePointer<CChar>] = params.capabilities.map { capability in
            let length = capability.lengthOfBytes(using: .utf8) + 1
            let buf = UnsafeMutablePointer<CChar>.allocate(capacity: length)
            capability.withCString { src in
                buf.initialize(from: src, count: length)
            }
            return buf
        }
        defer { capabilityCStringPtrs.forEach { $0.deallocate() } }
        let capsBuffer = UnsafeMutableBufferPointer<UnsafePointer<CChar>?>(
            start: .allocate(capacity: params.capabilities.count),
            count: params.capabilities.count
        )
        defer { capsBuffer.baseAddress?.deallocate() }
        for (i, ptr) in capabilityCStringPtrs.enumerated() { capsBuffer[i] = UnsafePointer(ptr) }

        var tokenPtr: UnsafeMutablePointer<UInt8>?
        var tokenLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            params.nonce.withUnsafeBytes { nonceRaw in
                rn_keys_ca_generate_enrollment_token(
                    params.eaKeyHandle,
                    params.tokenId,
                    params.networkId,
                    params.subject,
                    params.validFrom,
                    params.validUntil,
                    nonceRaw.bindMemory(to: UInt8.self).baseAddress,
                    params.nonce.count,
                    capsBuffer.baseAddress,
                    params.capabilities.count,
                    &tokenPtr,
                    &tokenLen,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
        guard code == 0 else {
            throw FFIError.operationFailed("Failed to generate enrollment token")
        }
        return try copyBytesAndFree(tokenPtr, tokenLen)
    }
    
    public static func free(_ handle: UnsafeMutableRawPointer) {
        rn_keys_ca_free_ea_key_pair(handle)
    }
}

public class CANode {
    public let ffiHandle: UnsafeMutableRawPointer
    
    public init(ffiHandle: UnsafeMutableRawPointer) {
        self.ffiHandle = ffiHandle
    }
    
    public static func create() throws -> CANode {
        var handle: UnsafeMutableRawPointer?
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_ca_node_new(&handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0, let out = handle else {
            throw FFIError.operationFailed("Failed to create CA Node")
        }
        return CANode(ffiHandle: out)
    }
    
    public func setupComplete(params: CANodeManager.CANodeSetupParams) throws {
        let (code, err) = withRnErrorCode { errPtr in
            params.rootCaSubject.withCString { cRoot in
                params.issuingCaSubject.withCString { cIssuing in
                    params.networkId.withCString { cNetworkId in
                        params.eaPublicKeys.withUnsafeBytes { raw in
                            rn_keys_ca_node_setup_complete(
                                self.ffiHandle,
                                cRoot,
                                cIssuing,
                                UInt32(params.validityDays),
                                UInt64(params.issuingCaSerial),
                                raw.bindMemory(to: UInt8.self).baseAddress,
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
        guard code == 0 else { throw FFIError.operationFailed("Failed to setup CA Node") }
    }
    
    public func createShared() throws -> UnsafeMutableRawPointer {
        var shared: UnsafeMutableRawPointer?
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_ca_node_create_shared(self.ffiHandle, &shared, errPtr)
        }
        if let error = err { throw error }
        guard code == 0, let out = shared else {
            throw FFIError.operationFailed("Failed to create shared CA Node")
        }
        return out
    }
    
    public static func freeShared(_ handle: UnsafeMutableRawPointer) {
        rn_keys_ca_node_free_shared(handle)
    }

    deinit {
        rn_keys_ca_node_free(ffiHandle)
    }
}

public class CANodeManager {
    public struct CANodeSetupParams {
        public let caNode: UnsafeMutableRawPointer
        public let rootCaSubject: String
        public let issuingCaSubject: String
        public let validityDays: Int
        public let issuingCaSerial: Int
        public let eaPublicKeys: Data
        public let networkId: String
    }
}

public class CAServer {
    
    private var handle: UnsafeMutableRawPointer?
    
    private init(handle: UnsafeMutableRawPointer) {
        self.handle = handle
    }
    
    public static func create(config: CaServerConfig, sharedCaNode: UnsafeMutableRawPointer) throws -> CAServer {
        // Encode to the CBOR config expected by rn_transport_ca_server_new
        let cborConfig = CustomCaServerConfig(
            bootstrap_bind: config.bootstrapBind,
            authenticated_bind: config.authenticatedBind,
            network_id: config.networkId,
            rate_limit_per_minute: config.rateLimitPerMinute,
            rate_limit_per_hour: config.rateLimitPerHour
        )
        let encoded = try CodableCBOREncoder().encode(cborConfig)
        var serverHandle: UnsafeMutableRawPointer?
        let (code, err) = withRnErrorCode { errPtr in
            encoded.withUnsafeBytes { raw in
                rn_transport_ca_server_new(
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    encoded.count,
                    sharedCaNode,
                    &serverHandle,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
        guard code == 0, let out = serverHandle else {
            throw FFIError.operationFailed("Failed to create CA Server")
        }
        return CAServer(handle: out)
    }
    
    public func stop() throws {
        guard let server = handle else { return }
        let (code, err) = withRnErrorCode { errPtr in
            rn_transport_ca_server_stop(server, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to stop CA Server") }
    }

    public func start() throws {
        guard let server = handle else { throw FFIError.invalidParameter("Server handle not initialized") }
        let (code, err) = withRnErrorCode { errPtr in
            rn_transport_ca_server_start(server, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to start CA Server") }
    }

    public func bootstrapAddress() throws -> String {
        guard let server = handle else { throw FFIError.invalidParameter("Server handle not initialized") }
        var out: UnsafeMutablePointer<CChar>?
        let (code, err) = withRnErrorCode { errPtr in
            rn_transport_ca_server_get_bootstrap_addr(server, &out, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get bootstrap address") }
        return try copyCStringAndFree(out)
    }

    public func authenticatedAddress() throws -> String {
        guard let server = handle else { throw FFIError.invalidParameter("Server handle not initialized") }
        var out: UnsafeMutablePointer<CChar>?
        let (code, err) = withRnErrorCode { errPtr in
            rn_transport_ca_server_get_authenticated_addr(server, &out, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get authenticated address") }
        return try copyCStringAndFree(out)
    }

    public func configureAdminSkis(_ skisCbor: Data) throws {
        guard let server = handle else { throw FFIError.invalidParameter("Server handle not initialized") }
        let (code, err) = withRnErrorCode { errPtr in
            skisCbor.withUnsafeBytes { raw in
                rn_transport_ca_server_configure_admin_skis(
                    server,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    skisCbor.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to configure admin SKIs") }
    }
    
    deinit {
        if let server = handle {
            rn_transport_ca_server_free(server)
            handle = nil
        }
    }
}

// MARK: - Shared CA Node Wrapper

public final class SharedCANode {
    public let handle: UnsafeMutableRawPointer

    public init(handle: UnsafeMutableRawPointer) {
        self.handle = handle
    }

    public func addAdminSki(_ ski: String) throws {
        let (code, err) = withRnErrorCode { errPtr in
            ski.withCString { cSki in
                rn_keys_ca_node_add_admin_ski(self.handle, cSki, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to add admin SKI") }
    }

    deinit {
        rn_keys_ca_node_free_shared(handle)
    }
}

// MARK: - CA Node Extensions

public extension CANode {
    func getRootCACertificate() throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_ca_node_get_root_ca_certificate(self.ffiHandle, &outPtr, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get Root CA certificate") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    func getIssuingCACertificate() throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_ca_node_get_issuing_ca_certificate(self.ffiHandle, &outPtr, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get Issuing CA certificate") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    func createSharedWrapped() throws -> SharedCANode {
        let raw = try self.createShared()
        return SharedCANode(handle: raw)
    }

    func handleCRL(networkId: String) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            networkId.withCString { cNet in
                rn_keys_ca_node_handle_crl(self.ffiHandle, cNet, &outPtr, &outLen, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to generate CRL-lite") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    func revokeToken(_ tokenId: String) throws {
        let (code, err) = withRnErrorCode { errPtr in
            tokenId.withCString { cToken in
                rn_keys_ca_node_revoke_token(self.ffiHandle, cToken, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to revoke token") }
    }
}

// MARK: - Keys Wrapper

public final class KeysHandle {
    public let handle: UnsafeMutableRawPointer

    public init() throws {
        var out: UnsafeMutableRawPointer?
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_new(&out, errPtr)
        }
        if let error = err { throw error }
        guard code == 0, let handle = out else { throw FFIError.operationFailed("Failed to create keys handle") }
        self.handle = handle
    }

    public func initializeAsNode() throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_init_as_node(self.handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to initialize as node") }
    }

    public func initializeAsMobile() throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_init_as_mobile(self.handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to initialize as mobile") }
    }

    public func generateCsrSetupToken() throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_node_generate_csr(self.handle, &outPtr, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to generate CSR setup token") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func installCertificate(_ certMessage: Data) throws {
        let (code, err) = withRnErrorCode { errPtr in
            certMessage.withUnsafeBytes { raw in
                rn_keys_node_install_certificate(
                    self.handle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    certMessage.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to install certificate") }
    }

    public func getQuicCertificateConfig() throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_node_get_quic_certificate_config(self.handle, &outPtr, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get QUIC certificate config") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func getNodeCertificate() throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_node_get_node_certificate(self.handle, &outPtr, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get node certificate") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func deriveUserProfileKey(label: String) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            label.withCString { cLabel in
                rn_keys_node_derive_user_profile_key(self.handle, cLabel, &outPtr, &outLen, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to derive user profile key") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func getCompactId(for key: Data) throws -> String {
        var outPtr: UnsafeMutablePointer<CChar>?
        let (code, err) = withRnErrorCode { errPtr in
            key.withUnsafeBytes { raw in
                rn_keys_get_compact_id(raw.bindMemory(to: UInt8.self).baseAddress, key.count, &outPtr, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get compact ID") }
        return try copyCStringAndFree(outPtr)
    }

    public func encryptWithEnvelope(plaintext: Data, profileKeys: [Data], networkKey: Data? = nil) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            plaintext.withUnsafeBytes { ptRaw in
                var keyPointers: [UnsafePointer<UInt8>?] = []
                var keyLengths: [Int] = []
                keyPointers.reserveCapacity(profileKeys.count)
                keyLengths.reserveCapacity(profileKeys.count)
                for k in profileKeys {
                    k.withUnsafeBytes { keyRaw in
                        keyPointers.append(keyRaw.bindMemory(to: UInt8.self).baseAddress)
                        keyLengths.append(k.count)
                    }
                }
                return keyPointers.withUnsafeBufferPointer { keysPtr in
                    keyLengths.withUnsafeBufferPointer { lensPtr in
                        rn_keys_node_encrypt_with_envelope(
                            self.handle,
                            ptRaw.bindMemory(to: UInt8.self).baseAddress,
                            plaintext.count,
                            nil,
                            0,
                            keysPtr.baseAddress,
                            lensPtr.baseAddress,
                            profileKeys.count,
                            &outPtr,
                            &outLen,
                            errPtr
                        )
                    }
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to encrypt with envelope") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func decryptWithProfile(envelope: Data, profileId: String) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            envelope.withUnsafeBytes { envRaw in
                profileId.withCString { cId in
                    rn_keys_node_decrypt_with_profile(
                        self.handle,
                        envRaw.bindMemory(to: UInt8.self).baseAddress,
                        envelope.count,
                        cId,
                        &outPtr,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to decrypt with profile") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func mobileFromEnrollResponse(_ response: Data) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            response.withUnsafeBytes { raw in
                rn_keys_mobile_from_enroll_response(self.handle, raw.bindMemory(to: UInt8.self).baseAddress, response.count, &outPtr, &outLen, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to convert enroll response") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func mobileFromRenewResponse(_ response: Data) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            response.withUnsafeBytes { raw in
                rn_keys_mobile_from_renew_response(self.handle, raw.bindMemory(to: UInt8.self).baseAddress, response.count, &outPtr, &outLen, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to convert renew response") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    // MARK: - Mobile-Specific Functions
    
    /// Initialize user root key for mobile device
    /// - Throws: FFIError if the operation fails
    public func mobileInitializeUserRootKey() throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_mobile_initialize_user_root_key(self.handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to initialize user root key") }
    }
    
    /// Get user public key for mobile device
    /// - Returns: User public key data
    /// - Throws: FFIError if the operation fails
    public func mobileGetUserPublicKey() throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_mobile_get_user_public_key(self.handle, &outPtr, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get user public key") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    /// Derive user profile key for mobile device
    /// - Parameter label: Profile label (e.g., "personal", "work")
    /// - Returns: Derived profile key data
    /// - Throws: FFIError if the operation fails
    public func mobileDeriveUserProfileKey(label: String) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            label.withCString { cLabel in
                rn_keys_mobile_derive_user_profile_key(self.handle, cLabel, &outPtr, &outLen, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to derive user profile key") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    /// Encrypt data with envelope for mobile device
    /// - Parameters:
    ///   - plaintext: Data to encrypt
    ///   - profileKeys: Array of profile keys for encryption
    ///   - networkKey: Optional network key
    /// - Returns: Encrypted envelope data
    /// - Throws: FFIError if the operation fails
    public func mobileEncryptWithEnvelope(plaintext: Data, profileKeys: [Data], networkKey: Data? = nil) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        
        // Prepare profile key pointers
        var profileKeyPtrs: [UnsafePointer<UInt8>?] = []
        var profileLens: [Int] = []
        
        for key in profileKeys {
            key.withUnsafeBytes { keyRaw in
                profileKeyPtrs.append(keyRaw.bindMemory(to: UInt8.self).baseAddress)
                profileLens.append(key.count)
            }
        }
        
        let (code, err) = withRnErrorCode { errPtr in
            plaintext.withUnsafeBytes { plaintextRaw in
                profileKeyPtrs.withUnsafeBufferPointer { keysPtr in
                    profileLens.withUnsafeBufferPointer { lensPtr in
                        if let networkKey = networkKey {
                            networkKey.withUnsafeBytes { networkRaw in
                                rn_keys_mobile_encrypt_with_envelope(
                                    self.handle,
                                    plaintextRaw.bindMemory(to: UInt8.self).baseAddress,
                                    plaintext.count,
                                    networkRaw.bindMemory(to: UInt8.self).baseAddress,
                                    networkKey.count,
                                    keysPtr.baseAddress,
                                    lensPtr.baseAddress,
                                    profileKeys.count,
                                    &outPtr,
                                    &outLen,
                                    errPtr
                                )
                            }
                        } else {
                            rn_keys_mobile_encrypt_with_envelope(
                                self.handle,
                                plaintextRaw.bindMemory(to: UInt8.self).baseAddress,
                                plaintext.count,
                                nil,
                                0,
                                keysPtr.baseAddress,
                                lensPtr.baseAddress,
                                profileKeys.count,
                                &outPtr,
                                &outLen,
                                errPtr
                            )
                        }
                    }
                }
            }
        }
        
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to encrypt with envelope") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    /// Decrypt envelope data for mobile device
    /// - Parameters:
    ///   - envelope: Encrypted envelope data
    /// - Returns: Decrypted data
    /// - Throws: FFIError if the operation fails
    public func mobileDecryptEnvelope(envelope: Data) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            envelope.withUnsafeBytes { envelopeRaw in
                rn_keys_mobile_decrypt_envelope(
                    self.handle,
                    envelopeRaw.bindMemory(to: UInt8.self).baseAddress,
                    envelope.count,
                    &outPtr,
                    &outLen,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to decrypt envelope") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    /// Process setup token (CSR) to create certificate
    /// - Parameter setupToken: Certificate signing request data
    /// - Returns: Certificate message data
    /// - Throws: FFIError if processing fails
    public func mobileProcessSetupToken(setupToken: Data) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            setupToken.withUnsafeBytes { raw in
                rn_keys_mobile_process_setup_token(
                    self.handle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    setupToken.count,
                    &outPtr,
                    &outLen,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to process setup token") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    /// Get node public key
    /// - Returns: Node public key data
    /// - Throws: FFIError if the operation fails
    public func getNodePublicKey() throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_node_get_public_key(self.handle, &outPtr, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get node public key") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    /// Set local node information
    /// - Parameter nodeInfoCbor: Node information in CBOR format
    /// - Throws: FFIError if the operation fails
    public func setLocalNodeInfo(nodeInfoCbor: Data) throws {
        let code = nodeInfoCbor.withUnsafeBytes { raw in
            rn_keys_set_local_node_info(self.handle, raw.bindMemory(to: UInt8.self).baseAddress, nodeInfoCbor.count)
        }
        guard code == 0 else { 
            // Try to get more details about the error
            var errorBuffer = [CChar](repeating: 0, count: 256)
            let _ = rn_last_error(&errorBuffer, 256)
            let errorMessage = String(decoding: errorBuffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            throw FFIError.operationFailed("Failed to set local node info (code: \(code)): \(errorMessage)") 
        }
    }

    deinit {
        rn_keys_free(handle)
    }
}

// MARK: - CA Client Wrapper

public final class CAClient {
    public let handle: UnsafeMutableRawPointer

    public init(config: CaClientConfigAll, nodeKeys: KeysHandle) throws {
        let cbor = try CodableCBOREncoder().encode(config)
        var out: UnsafeMutableRawPointer?
        let (code, err) = withRnErrorCode { errPtr in
            cbor.withUnsafeBytes { raw in
                rn_transport_ca_client_new_with_config(raw.bindMemory(to: UInt8.self).baseAddress, cbor.count, nodeKeys.handle, &out, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0, let handle = out else { throw FFIError.operationFailed("Failed to create CA client") }
        self.handle = handle
    }

    public func enroll(bootstrapAddress: String, request: Data) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            bootstrapAddress.withCString { cAddr in
                request.withUnsafeBytes { raw in
                    rn_transport_ca_client_enroll(self.handle, cAddr, raw.bindMemory(to: UInt8.self).baseAddress, request.count, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to enroll") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func renew(authenticatedAddress: String, request: Data) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            authenticatedAddress.withCString { cAddr in
                request.withUnsafeBytes { raw in
                    rn_transport_ca_client_renew(self.handle, cAddr, raw.bindMemory(to: UInt8.self).baseAddress, request.count, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to renew certificate") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func revoke(authenticatedAddress: String, request: Data) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            authenticatedAddress.withCString { cAddr in
                request.withUnsafeBytes { raw in
                    rn_transport_ca_client_revoke(self.handle, cAddr, raw.bindMemory(to: UInt8.self).baseAddress, request.count, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to revoke certificate") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func getStatus(authenticatedAddress: String, networkId: String) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            authenticatedAddress.withCString { cAddr in
                networkId.withCString { cNet in
                    rn_transport_ca_client_get_status(self.handle, cAddr, cNet, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get status") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func getChain(bootstrapAddress: String, networkId: String) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            bootstrapAddress.withCString { cAddr in
                networkId.withCString { cNet in
                    rn_transport_ca_client_get_chain(self.handle, cAddr, cNet, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get chain") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    deinit {
        rn_transport_ca_client_free(handle)
    }
}

// MARK: - Certificate Utilities

public enum CertificateUtils {
    public static func extractSki(from certificateDer: Data) throws -> String {
        var outPtr: UnsafeMutablePointer<CChar>?
        let (code, err) = withRnErrorCode { errPtr in
            certificateDer.withUnsafeBytes { raw in
                rn_keys_certificate_extract_ski(raw.bindMemory(to: UInt8.self).baseAddress, certificateDer.count, &outPtr, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to extract SKI") }
        return try copyCStringAndFree(outPtr)
    }

    public static func getSerialHex(from certificateDer: Data) throws -> String {
        var outPtr: UnsafeMutablePointer<CChar>?
        let (code, err) = withRnErrorCode { errPtr in
            certificateDer.withUnsafeBytes { raw in
                rn_keys_certificate_get_serial(raw.bindMemory(to: UInt8.self).baseAddress, certificateDer.count, &outPtr, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get serial") }
        return try copyCStringAndFree(outPtr)
    }
}

// MARK: - CBOR Structures for Transport

/// Swift representation of NodeInfo structure from Rust
public struct NodeInfo: Codable {
    public let nodePublicKey: Data
    public let networkIds: [String]
    public let addresses: [String]
    public let nodeMetadata: NodeMetadata
    public let version: Int64
    
    public init(nodePublicKey: Data, networkIds: [String], addresses: [String], nodeMetadata: NodeMetadata, version: Int64) {
        self.nodePublicKey = nodePublicKey
        self.networkIds = networkIds
        self.addresses = addresses
        self.nodeMetadata = nodeMetadata
        self.version = version
    }
    
    enum CodingKeys: String, CodingKey {
        case nodePublicKey = "node_public_key"
        case networkIds = "network_ids"
        case addresses
        case nodeMetadata = "node_metadata"
        case version
    }
}

/// Swift representation of NodeMetadata structure from Rust
public struct NodeMetadata: Codable {
    public let services: [ServiceMetadata]
    public let subscriptions: [SubscriptionMetadata]
    
    public init(services: [ServiceMetadata], subscriptions: [SubscriptionMetadata]) {
        self.services = services
        self.subscriptions = subscriptions
    }
}

/// Swift representation of ServiceMetadata structure from Rust
public struct ServiceMetadata: Codable {
    public let networkId: String
    public let servicePath: String
    public let name: String
    public let version: String
    public let description: String
    public let actions: [ActionMetadata]
    public let registrationTime: UInt64
    public let lastStartTime: UInt64?
    
    public init(networkId: String, servicePath: String, name: String, version: String, description: String, actions: [ActionMetadata], registrationTime: UInt64, lastStartTime: UInt64? = nil) {
        self.networkId = networkId
        self.servicePath = servicePath
        self.name = name
        self.version = version
        self.description = description
        self.actions = actions
        self.registrationTime = registrationTime
        self.lastStartTime = lastStartTime
    }
    
    enum CodingKeys: String, CodingKey {
        case networkId = "network_id"
        case servicePath = "service_path"
        case name
        case version
        case description
        case actions
        case registrationTime = "registration_time"
        case lastStartTime = "last_start_time"
    }
}

/// Swift representation of ActionMetadata structure from Rust
public struct ActionMetadata: Codable {
    public let name: String
    public let description: String
    public let inputSchema: FieldSchema?
    public let outputSchema: FieldSchema?
    
    public init(name: String, description: String, inputSchema: FieldSchema? = nil, outputSchema: FieldSchema? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
        case outputSchema = "output_schema"
    }
}

/// Swift representation of SubscriptionMetadata structure from Rust
public struct SubscriptionMetadata: Codable {
    public let path: String
    
    public init(path: String) {
        self.path = path
    }
}

/// Swift representation of FieldSchema structure from Rust
public struct FieldSchema: Codable {
    public let dataType: SchemaDataType
    public let required: Bool
    public let description: String?
    
    public init(dataType: SchemaDataType, required: Bool, description: String? = nil) {
        self.dataType = dataType
        self.required = required
        self.description = description
    }
    
    enum CodingKeys: String, CodingKey {
        case dataType = "data_type"
        case required
        case description
    }
}

/// Swift representation of SchemaDataType enum from Rust
public enum SchemaDataType: String, Codable {
    case string = "String"
    case int32 = "Int32"
    case int64 = "Int64"
    case float32 = "Float32"
    case float64 = "Float64"
    case boolean = "Boolean"
    case bytes = "Bytes"
    case array = "Array"
    case map = "Map"
}

/// Swift representation of QuicTransportOptions for CBOR encoding
public struct QuicTransportOptionsCbor: Codable {
    public let bindAddr: String?
    public let handshakeTimeoutMs: UInt64?
    public let openStreamTimeoutMs: UInt64?
    public let maxMessageSize: UInt64?
    public let responseCacheTtlMs: UInt64?
    public let maxRequestRetries: UInt32?
    
    public init(bindAddr: String? = nil, handshakeTimeoutMs: UInt64? = nil, openStreamTimeoutMs: UInt64? = nil, maxMessageSize: UInt64? = nil, responseCacheTtlMs: UInt64? = nil, maxRequestRetries: UInt32? = nil) {
        self.bindAddr = bindAddr
        self.handshakeTimeoutMs = handshakeTimeoutMs
        self.openStreamTimeoutMs = openStreamTimeoutMs
        self.maxMessageSize = maxMessageSize
        self.responseCacheTtlMs = responseCacheTtlMs
        self.maxRequestRetries = maxRequestRetries
    }
    
    enum CodingKeys: String, CodingKey {
        case bindAddr = "bind_addr"
        case handshakeTimeoutMs = "handshake_timeout_ms"
        case openStreamTimeoutMs = "open_stream_timeout_ms"
        case maxMessageSize = "max_message_size"
        case responseCacheTtlMs = "response_cache_ttl_ms"
        case maxRequestRetries = "max_request_retries"
    }
}

// MARK: - CBOR Encoding Helpers

/// Helper functions for creating CBOR-encoded data
public struct CBORHelper {
    /// Create a minimal NodeInfo for testing
    public static func createMinimalNodeInfo(nodePublicKey: Data, networkId: String = "test-network") -> NodeInfo {
        let serviceMetadata = ServiceMetadata(
            networkId: networkId,
            servicePath: "/test",
            name: "test-service",
            version: "1.0.0",
            description: "Test service",
            actions: [],
            registrationTime: UInt64(Date().timeIntervalSince1970)
        )
        
        let nodeMetadata = NodeMetadata(
            services: [serviceMetadata],
            subscriptions: []
        )
        
        return NodeInfo(
            nodePublicKey: nodePublicKey,
            networkIds: [networkId],
            addresses: ["127.0.0.1:0"], // Will be updated by transport
            nodeMetadata: nodeMetadata,
            version: 1
        )
    }
    
    /// Create minimal transport options for testing
    public static func createMinimalTransportOptions(bindAddr: String = "127.0.0.1:0") -> QuicTransportOptionsCbor {
        return QuicTransportOptionsCbor(
            bindAddr: bindAddr,
            handshakeTimeoutMs: 5000,
            maxMessageSize: 1024,
            maxRequestRetries: 3
        )
    }
    
    /// Encode NodeInfo to CBOR data
    public static func encodeNodeInfo(_ nodeInfo: NodeInfo) throws -> Data {
        // Create CBOR map manually to match Rust structure
        var map: [CBOR: CBOR] = [:]
        map[.utf8String("node_public_key")] = .array([UInt8](nodeInfo.nodePublicKey).map { .unsignedInt(UInt64($0)) })
        map[.utf8String("network_ids")] = .array(nodeInfo.networkIds.map { .utf8String($0) })
        map[.utf8String("addresses")] = .array(nodeInfo.addresses.map { .utf8String($0) })
        
        // Encode node metadata
        var metadataMap: [CBOR: CBOR] = [:]
        metadataMap[.utf8String("services")] = .array(nodeInfo.nodeMetadata.services.map { service in
            var serviceMap: [CBOR: CBOR] = [:]
            serviceMap[.utf8String("network_id")] = .utf8String(service.networkId)
            serviceMap[.utf8String("service_path")] = .utf8String(service.servicePath)
            serviceMap[.utf8String("name")] = .utf8String(service.name)
            serviceMap[.utf8String("version")] = .utf8String(service.version)
            serviceMap[.utf8String("description")] = .utf8String(service.description)
            serviceMap[.utf8String("actions")] = .array([])
            serviceMap[.utf8String("registration_time")] = .unsignedInt(service.registrationTime)
            return .map(serviceMap)
        })
        metadataMap[.utf8String("subscriptions")] = .array([])
        
        map[.utf8String("node_metadata")] = .map(metadataMap)
        map[.utf8String("version")] = .unsignedInt(UInt64(nodeInfo.version))
        
        return Data(CBOR.map(map).encode())
    }
    
    /// Encode QuicTransportOptions to CBOR data
    public static func encodeTransportOptions(_ options: QuicTransportOptionsCbor) throws -> Data {
        // Create CBOR map manually to match Rust structure
        var map: [CBOR: CBOR] = [:]
        
        if let bindAddr = options.bindAddr {
            map[.utf8String("bind_addr")] = .utf8String(bindAddr)
        }
        if let handshakeTimeoutMs = options.handshakeTimeoutMs {
            map[.utf8String("handshake_timeout_ms")] = .unsignedInt(handshakeTimeoutMs)
        }
        if let openStreamTimeoutMs = options.openStreamTimeoutMs {
            map[.utf8String("open_stream_timeout_ms")] = .unsignedInt(openStreamTimeoutMs)
        }
        if let maxMessageSize = options.maxMessageSize {
            map[.utf8String("max_message_size")] = .unsignedInt(maxMessageSize)
        }
        if let responseCacheTtlMs = options.responseCacheTtlMs {
            map[.utf8String("response_cache_ttl_ms")] = .unsignedInt(responseCacheTtlMs)
        }
        if let maxRequestRetries = options.maxRequestRetries {
            map[.utf8String("max_request_retries")] = .unsignedInt(UInt64(maxRequestRetries))
        }
        
        return Data(CBOR.map(map).encode())
    }
    
    /// Encode PeerInfo to CBOR data
    public static func encodePeerInfo(_ peerInfo: PeerInfo) throws -> Data {
        // Create CBOR map manually to match Rust structure
        var map: [CBOR: CBOR] = [:]
        map[.utf8String("public_key")] = .array([UInt8](peerInfo.publicKey).map { .unsignedInt(UInt64($0)) })
        map[.utf8String("addresses")] = .array(peerInfo.addresses.map { .utf8String($0) })
        
        return Data(CBOR.map(map).encode())
    }
    
    /// Encode TransportRequestParams to CBOR data using proper struct serialization
    public static func encodeTransportRequestParams(_ params: TransportRequestParams) throws -> Data {
        // Use proper CBOR encoding like Rust does with serde_cbor
        let encoder = CodableCBOREncoder()
        return try encoder.encode(params)
    }
    
    /// Encode TransportCompleteRequestParams to CBOR data using proper struct serialization
    public static func encodeTransportCompleteRequestParams(_ params: TransportCompleteRequestParams) throws -> Data {
        // Use proper CBOR encoding like Rust does with serde_cbor
        let encoder = CodableCBOREncoder()
        return try encoder.encode(params)
    }
}

// MARK: - Transport Request/Response Structures

/// Swift representation of TransportRequestParams from Rust FFI
public struct TransportRequestParams: Codable {
    public let path: String
    public let correlationId: String
    public let payload: Data
    public let destPeerId: String
    public let networkPublicKey: Data?
    public let profilePublicKeys: [Data]
    
    public init(path: String, correlationId: String, payload: Data, destPeerId: String, networkPublicKey: Data? = nil, profilePublicKeys: [Data] = []) {
        self.path = path
        self.correlationId = correlationId
        self.payload = payload
        self.destPeerId = destPeerId
        self.networkPublicKey = networkPublicKey
        self.profilePublicKeys = profilePublicKeys
    }
    
    enum CodingKeys: String, CodingKey {
        case path
        case correlationId = "correlation_id"
        case payload
        case destPeerId = "dest_peer_id"
        case networkPublicKey = "network_public_key"
        case profilePublicKeys = "profile_public_keys"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(correlationId, forKey: .correlationId)
        try container.encode(Array(payload), forKey: .payload)
        try container.encode(destPeerId, forKey: .destPeerId)
        if let networkPublicKey = networkPublicKey {
            try container.encode(Array(networkPublicKey), forKey: .networkPublicKey)
        }
        try container.encode(profilePublicKeys.map { Array($0) }, forKey: .profilePublicKeys)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        correlationId = try container.decode(String.self, forKey: .correlationId)
        let payloadBytes = try container.decode([UInt8].self, forKey: .payload)
        payload = Data(payloadBytes)
        destPeerId = try container.decode(String.self, forKey: .destPeerId)
        if let networkBytes = try? container.decode([UInt8].self, forKey: .networkPublicKey) {
            networkPublicKey = Data(networkBytes)
        } else {
            networkPublicKey = nil
        }
        let profileBytesArray = try container.decode([[UInt8]].self, forKey: .profilePublicKeys)
        profilePublicKeys = profileBytesArray.map { Data($0) }
    }
}

/// Swift representation of TransportCompleteRequestParams from Rust FFI
public struct TransportCompleteRequestParams: Codable {
    public let requestId: String
    public let responsePayload: Data
    public let profilePublicKeys: [Data]
    
    public init(requestId: String, responsePayload: Data, profilePublicKeys: [Data] = []) {
        self.requestId = requestId
        self.responsePayload = responsePayload
        self.profilePublicKeys = profilePublicKeys
    }
    
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case responsePayload = "response_payload"
        case profilePublicKeys = "profile_public_keys"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(Array(responsePayload), forKey: .responsePayload)
        try container.encode(profilePublicKeys.map { Array($0) }, forKey: .profilePublicKeys)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try container.decode(String.self, forKey: .requestId)
        let responseBytes = try container.decode([UInt8].self, forKey: .responsePayload)
        responsePayload = Data(responseBytes)
        let profileBytesArray = try container.decode([[UInt8]].self, forKey: .profilePublicKeys)
        profilePublicKeys = profileBytesArray.map { Data($0) }
    }
}

/// Swift representation of PeerInfo from Rust
public struct PeerInfo: Codable {
    public let publicKey: Data
    public let addresses: [String]
    
    public init(publicKey: Data, addresses: [String]) {
        self.publicKey = publicKey
        self.addresses = addresses
    }
    
    enum CodingKeys: String, CodingKey {
        case publicKey = "public_key"
        case addresses
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Array(publicKey), forKey: .publicKey)
        try container.encode(addresses, forKey: .addresses)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let publicKeyBytes = try container.decode([UInt8].self, forKey: .publicKey)
        publicKey = Data(publicKeyBytes)
        addresses = try container.decode([String].self, forKey: .addresses)
    }
}

// MARK: - Discovery Options

/// Swift representation of DiscoveryOptions from Rust FFI
public struct DiscoveryOptions: Codable {
    public let multicastGroup: String
    public let announceIntervalMs: UInt32
    public let discoveryTimeoutMs: UInt32
    public let debounceWindowMs: UInt32
    
    public init(multicastGroup: String = "224.0.0.251:5353", 
                announceIntervalMs: UInt32 = 1000,
                discoveryTimeoutMs: UInt32 = 5000,
                debounceWindowMs: UInt32 = 200) {
        self.multicastGroup = multicastGroup
        self.announceIntervalMs = announceIntervalMs
        self.discoveryTimeoutMs = discoveryTimeoutMs
        self.debounceWindowMs = debounceWindowMs
    }
    
    enum CodingKeys: String, CodingKey {
        case multicastGroup = "multicast_group"
        case announceIntervalMs = "announce_interval_ms"
        case discoveryTimeoutMs = "discovery_timeout_ms"
        case debounceWindowMs = "debounce_window_ms"
    }
}

// MARK: - Discovery Handle

/// Handle for Discovery operations
public class DiscoveryHandle {
    private let handle: UnsafeMutableRawPointer
    
    private init(handle: UnsafeMutableRawPointer) {
        self.handle = handle
    }
    
    deinit {
        rn_discovery_free(handle)
    }
    
    /// Create a new discovery instance with multicast
    public static func create(keys: KeysHandle, optionsCbor: Data) throws -> DiscoveryHandle {
        var outPtr: UnsafeMutableRawPointer?
        let (code, err) = withRnErrorCode { errPtr in
            optionsCbor.withUnsafeBytes { raw in
                rn_discovery_new_with_multicast(
                    keys.handle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    optionsCbor.count,
                    &outPtr,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to create discovery") }
        guard let handle = outPtr else { throw FFIError.operationFailed("Discovery handle is null") }
        return DiscoveryHandle(handle: handle)
    }
    
    /// Initialize discovery with options
    public func initialize(optionsCbor: Data) throws {
        let (code, err) = withRnErrorCode { errPtr in
            optionsCbor.withUnsafeBytes { raw in
                rn_discovery_init(
                    self.handle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    optionsCbor.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to initialize discovery") }
    }
    
    /// Bind discovery events to transport
    public func bindEventsToTransport(transport: TransportHandle) throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_discovery_bind_events_to_transport(
                self.handle,
                transport.rawHandle,
                errPtr
            )
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to bind discovery events to transport") }
    }
    
    /// Start announcing this node
    public func startAnnouncing() throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_discovery_start_announcing(self.handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to start announcing") }
    }
    
    /// Stop announcing this node
    public func stopAnnouncing() throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_discovery_stop_announcing(self.handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to stop announcing") }
    }
    
    /// Shutdown discovery
    public func shutdown() throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_discovery_shutdown(self.handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to shutdown discovery") }
    }
    
    /// Update local peer info
    public func updateLocalPeerInfo(peerInfoCbor: Data) throws {
        let (code, err) = withRnErrorCode { errPtr in
            peerInfoCbor.withUnsafeBytes { raw in
                rn_discovery_update_local_peer_info(
                    self.handle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    peerInfoCbor.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to update local peer info") }
    }
}

// MARK: - Transport Handle

/// Handle for QUIC Transport operations
public class TransportHandle {
    private let handle: UnsafeMutableRawPointer
    
    private init(handle: UnsafeMutableRawPointer) {
        self.handle = handle
    }
    
    /// Get the raw handle for internal use
    internal var rawHandle: UnsafeMutableRawPointer {
        return handle
    }
    
    deinit {
        rn_transport_free(handle)
    }
    
    /// Create a new transport instance with keys
    /// - Parameters:
    ///   - keys: Keys handle instance
    ///   - optionsCbor: Transport options in CBOR format
    /// - Returns: New transport handle
    /// - Throws: FFIError if creation fails
    public static func create(keys: KeysHandle, optionsCbor: Data) throws -> TransportHandle {
        var outTransport: UnsafeMutableRawPointer?
        let (code, err) = withRnErrorCode { errPtr in
            optionsCbor.withUnsafeBytes { raw in
                rn_transport_new_with_keys(keys.handle, raw.bindMemory(to: UInt8.self).baseAddress, optionsCbor.count, &outTransport, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0, let transport = outTransport else { 
            throw FFIError.operationFailed("Failed to create transport") 
        }
        return TransportHandle(handle: transport)
    }
    
    /// Start the transport
    /// - Throws: FFIError if start fails
    public func start() throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_transport_start(handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to start transport") }
    }
    
    /// Poll for events
    /// - Returns: Event data if available, nil if no events
    /// - Throws: FFIError if polling fails
    public func pollEvent() throws -> Data? {
        var outEvent: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            rn_transport_poll_event(handle, &outEvent, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to poll event") }
        
        if outLen == 0 {
            return nil
        }
        
        return try copyBytesAndFree(outEvent, outLen)
    }
    
    /// Connect to a peer
    /// - Parameter peerInfoCbor: Peer information in CBOR format
    /// - Throws: FFIError if connection fails
    public func connectPeer(peerInfoCbor: Data) throws {
        let (code, err) = withRnErrorCode { errPtr in
            peerInfoCbor.withUnsafeBytes { raw in
                rn_transport_connect_peer(handle, raw.bindMemory(to: UInt8.self).baseAddress, peerInfoCbor.count, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to connect to peer") }
    }
    
    /// Disconnect from a peer
    /// - Parameter peerNodeId: Node ID of the peer to disconnect
    /// - Throws: FFIError if disconnection fails
    public func disconnectPeer(peerNodeId: String) throws {
        let (code, err) = withRnErrorCode { errPtr in
            peerNodeId.withCString { cString in
                rn_transport_disconnect_peer(handle, cString, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to disconnect from peer") }
    }
    
    /// Check if connected to a peer
    /// - Parameter peerNodeId: Node ID of the peer to check
    /// - Returns: True if connected, false otherwise
    /// - Throws: FFIError if check fails
    public func isConnected(peerNodeId: String) throws -> Bool {
        var outConnected: Bool = false
        let (code, err) = withRnErrorCode { errPtr in
            peerNodeId.withCString { cString in
                rn_transport_is_connected(handle, cString, &outConnected, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to check connection status") }
        return outConnected
    }
    
    /// Update local node information
    /// - Parameter nodeInfoCbor: Node information in CBOR format
    /// - Throws: FFIError if update fails
    public func updateLocalNodeInfo(nodeInfoCbor: Data) throws {
        let (code, err) = withRnErrorCode { errPtr in
            nodeInfoCbor.withUnsafeBytes { raw in
                rn_transport_update_local_node_info(handle, raw.bindMemory(to: UInt8.self).baseAddress, nodeInfoCbor.count, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to update local node info") }
    }
    
    /// Send a request
    /// - Parameter requestCbor: Request data in CBOR format
    /// - Throws: FFIError if request fails
    public func request(requestCbor: Data) throws {
        let (code, err) = withRnErrorCode { errPtr in
            requestCbor.withUnsafeBytes { raw in
                rn_transport_request(handle, raw.bindMemory(to: UInt8.self).baseAddress, requestCbor.count, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to send request") }
    }
    
    /// Publish an event
    /// - Parameter publishCbor: Event data in CBOR format
    /// - Throws: FFIError if publish fails
    public func publish(publishCbor: Data) throws {
        let (code, err) = withRnErrorCode { errPtr in
            publishCbor.withUnsafeBytes { raw in
                rn_transport_publish(handle, raw.bindMemory(to: UInt8.self).baseAddress, publishCbor.count, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to publish event") }
    }
    
    /// Complete a request
    /// - Parameter completeCbor: Completion data in CBOR format
    /// - Throws: FFIError if completion fails
    public func completeRequest(completeCbor: Data) throws {
        let (code, err) = withRnErrorCode { errPtr in
            completeCbor.withUnsafeBytes { raw in
                rn_transport_complete_request(handle, raw.bindMemory(to: UInt8.self).baseAddress, completeCbor.count, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to complete request") }
    }
    
    /// Stop the transport
    /// - Throws: FFIError if stop fails
    public func stop() throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_transport_stop(handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to stop transport") }
    }
    
    /// Get local address
    /// - Returns: Local address string
    /// - Throws: FFIError if getting address fails
    public func getLocalAddr() throws -> String {
        var outStr: UnsafeMutablePointer<CChar>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            rn_transport_local_addr(handle, &outStr, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get local address") }
        
        defer {
            if let str = outStr {
                rn_string_free(str)
            }
        }
        
        guard let str = outStr else { throw FFIError.operationFailed("No local address returned") }
        return String(cString: str)
    }
}
