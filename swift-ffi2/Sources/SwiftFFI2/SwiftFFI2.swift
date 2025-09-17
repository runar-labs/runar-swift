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
    public enum LogLevel: String, CaseIterable {
        case trace = "TRACE"
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }
    
    public static func setLogLevel(_ level: LogLevel) {
        // Integrate with SwiftCommon logger configuration if needed. No stdout prints here.
    }
    
    public static func log(_ level: LogLevel, _ message: String) {
        // Library must not print. Rely on SwiftCommon's RunarLogger in call sites.
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
