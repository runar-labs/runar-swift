import CRunarFFI
import Foundation

// MARK: - CA Server Configuration

/// CA Server Configuration - Swift equivalent of RNAPICaServerConfig
public struct CaServerConfig {
    public let bootstrapBind: String
    public let authenticatedBind: String
    public let networkId: String
    public let rateLimitPerMinute: UInt32
    public let rateLimitPerHour: UInt32

    public init(
        bootstrapBind: String,
        authenticatedBind: String,
        networkId: String,
        rateLimitPerMinute: UInt32,
        rateLimitPerHour: UInt32
    ) {
        self.bootstrapBind = bootstrapBind
        self.authenticatedBind = authenticatedBind
        self.networkId = networkId
        self.rateLimitPerMinute = rateLimitPerMinute
        self.rateLimitPerHour = rateLimitPerHour
    }

    /// Convert to C-compatible structure for FFI calls
    func toCStruct() -> RNAPICaServerConfig {
        RNAPICaServerConfig(
            bootstrap_bind: bootstrapBind,
            authenticated_bind: authenticatedBind,
            network_id: networkId,
            rate_limit_per_minute: rateLimitPerMinute,
            rate_limit_per_hour: rateLimitPerHour
        )
    }
}

// MARK: - CaServerConfig Codable Support

extension CaServerConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case bootstrapBind = "bootstrap_bind"
        case authenticatedBind = "authenticated_bind"
        case networkId = "network_id"
        case rateLimitPerMinute = "rate_limit_per_minute"
        case rateLimitPerHour = "rate_limit_per_hour"
    }
}

// MARK: - CA Client Configuration

/// CA Client Configuration - Swift equivalent of RNAPICaClientConfig
public struct CaClientConfig {
    public let bootstrapServer: String
    public let authenticatedServer: String
    public let networkId: String
    public let requestTimeoutSeconds: UInt32
    public let maxRetries: UInt32

    public init(
        bootstrapServer: String,
        authenticatedServer: String,
        networkId: String,
        requestTimeoutSeconds: UInt32,
        maxRetries: UInt32
    ) {
        self.bootstrapServer = bootstrapServer
        self.authenticatedServer = authenticatedServer
        self.networkId = networkId
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.maxRetries = maxRetries
    }

    /// Convert to C-compatible structure for FFI calls
    func toCStruct() -> RNAPICaClientConfig {
        RNAPICaClientConfig(
            bootstrap_server: bootstrapServer,
            authenticated_server: authenticatedServer,
            network_id: networkId,
            request_timeout_seconds: requestTimeoutSeconds,
            max_retries: maxRetries
        )
    }
}

// MARK: - CaClientConfig Codable Support

extension CaClientConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case bootstrapServer = "bootstrap_server"
        case authenticatedServer = "authenticated_server"
        case networkId = "network_id"
        case requestTimeoutSeconds = "request_timeout_seconds"
        case maxRetries = "max_retries"
    }
}

// MARK: - Certificate Status

/// Certificate Status - Swift equivalent of RNAPICertificateStatus
public struct CertificateStatus {
    public let isValid: Bool
    public let notBefore: UInt64
    public let notAfter: UInt64
    public let serialHex: String

    public init(
        isValid: Bool,
        notBefore: UInt64,
        notAfter: UInt64,
        serialHex: String
    ) {
        self.isValid = isValid
        self.notBefore = notBefore
        self.notAfter = notAfter
        self.serialHex = serialHex
    }

    /// Convert from C-compatible structure
    static func fromCStruct(_ cStruct: RNAPICertificateStatus) -> CertificateStatus {
        let serialHex = cStruct.serial_hex.map { String(cString: $0) } ?? ""
        return CertificateStatus(
            isValid: cStruct.is_valid != 0,
            notBefore: cStruct.not_before,
            notAfter: cStruct.not_after,
            serialHex: serialHex
        )
    }
}

// MARK: - Profile Key Info

/// Profile Key Info - Swift equivalent of RNAPIProfileKeyInfo
public struct ProfileKeyInfo {
    public let profileId: String
    public let publicKey: Data

    public init(profileId: String, publicKey: Data) {
        self.profileId = profileId
        self.publicKey = publicKey
    }

    /// Convert from C-compatible structure
    static func fromCStruct(_ cStruct: RNAPIProfileKeyInfo) -> ProfileKeyInfo {
        let profileId = cStruct.profile_id.map { String(cString: $0) } ?? ""
        let publicKey = Data(bytes: cStruct.public_key, count: cStruct.public_key_len)
        return ProfileKeyInfo(profileId: profileId, publicKey: publicKey)
    }
}

// MARK: - FFI Handles

/// FFI Keys Handle - Swift equivalent of RNAPIFfiKeysHandle
public struct FfiKeysHandle {
    let inner: UnsafeMutableRawPointer
}

/// FFI Transport Handle - Swift equivalent of RNAPIFfiTransportHandle
public struct FfiTransportHandle {
    let inner: UnsafeMutableRawPointer
}

// MARK: - Memory Management Helpers

/// Helper functions for managing FFI-allocated memory
public enum FFIMemoryManager {
    /// Free FFI-allocated buffer
    public static func free(_ pointer: UnsafeMutablePointer<UInt8>, length: Int) {
        rn_free(pointer, length)
    }

    /// Free FFI-allocated string
    public static func freeString(_ pointer: UnsafePointer<CChar>) {
        rn_string_free(pointer)
    }

    /// Free FFI-allocated data with proper cleanup
    public static func freeData(_ data: Data, pointer: UnsafeMutablePointer<UInt8>) {
        rn_free(pointer, data.count)
    }
}

// MARK: - CBOR Data Structures for FFI Communication

/// CA Client Configuration with all options (CBOR-serialized) - EXACTLY matching Rust
public struct CaClientConfigAll: Codable {
    public let bootstrap_server: String
    public let authenticated_server: String
    public let network_id: String
    public let request_timeout_seconds: UInt32
    public let max_retries: UInt32
    public let root_ca_der: Data // Required, not optional
    public let issuing_ca_der: Data // Required, not optional
    
    public init(bootstrap_server: String, authenticated_server: String, network_id: String, request_timeout_seconds: UInt32, max_retries: UInt32, root_ca_der: Data, issuing_ca_der: Data) {
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
        
        // Handle Data fields as CBOR bytes (matching Rust serde_bytes)
        if let rootCaDerBytes = try? container.decode([UInt8].self, forKey: .root_ca_der) {
            root_ca_der = Data(rootCaDerBytes)
        } else {
            root_ca_der = try container.decode(Data.self, forKey: .root_ca_der)
        }
        
        if let issuingCaDerBytes = try? container.decode([UInt8].self, forKey: .issuing_ca_der) {
            issuing_ca_der = Data(issuingCaDerBytes)
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

/// Custom CA Server Configuration
public struct CustomCaServerConfig: Codable {
    public let bootstrap_bind: String
    public let authenticated_bind: String
    public let network_id: String
    public let rate_limit_per_minute: UInt32
    public let rate_limit_per_hour: UInt32
}

/// Revoke Request - EXACTLY matching Rust
public struct RevokeRequest: Codable {
    public let network_id: String
    public let certificate_serial: [UInt8] // Convert hex string to bytes (CBOR sequence, not byte string)
    public let reason: String
}

/// CsrEnrollRequest structure matching Rust implementation exactly
public struct CsrEnrollRequest: Codable {
    public let network_id: String
    public let csr_der: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
    public let enrollment_token: EnrollmentToken
}

/// RenewRequest structure matching Rust implementation exactly
public struct RenewRequest: Codable {
    public let network_id: String
    public let csr_der: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
}

/// SetupToken structure matching Rust implementation exactly
public struct SetupToken: Codable {
    public let node_public_key: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
    public let node_agreement_public_key: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
    public let csr_der: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
    public let node_id: String
    
    enum CodingKeys: String, CodingKey {
        case node_public_key
        case node_agreement_public_key
        case csr_der
        case node_id
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        node_public_key = try container.decode([UInt8].self, forKey: .node_public_key)
        node_agreement_public_key = try container.decode([UInt8].self, forKey: .node_agreement_public_key)
        csr_der = try container.decode([UInt8].self, forKey: .csr_der)
        node_id = try container.decode(String.self, forKey: .node_id)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(node_public_key, forKey: .node_public_key)
        try container.encode(node_agreement_public_key, forKey: .node_agreement_public_key)
        try container.encode(csr_der, forKey: .csr_der)
        try container.encode(node_id, forKey: .node_id)
    }
}

/// EnrollmentTokenBody structure matching Rust implementation exactly
public struct EnrollmentTokenBody: Codable {
    public let token_id: String
    public let network_id: String
    public let subject_hint: String?
    public let not_before: UInt64
    public let expires_at: UInt64
    public let nonce: [UInt8] // Rust uses [u8; 16], Swift uses [UInt8]
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
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        token_id = try container.decode(String.self, forKey: .token_id)
        network_id = try container.decode(String.self, forKey: .network_id)
        subject_hint = try container.decodeIfPresent(String.self, forKey: .subject_hint)
        not_before = try container.decode(UInt64.self, forKey: .not_before)
        expires_at = try container.decode(UInt64.self, forKey: .expires_at)
        nonce = try container.decode([UInt8].self, forKey: .nonce)
        permissions = try container.decode([String].self, forKey: .permissions)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token_id, forKey: .token_id)
        try container.encode(network_id, forKey: .network_id)
        try container.encodeIfPresent(subject_hint, forKey: .subject_hint)
        try container.encode(not_before, forKey: .not_before)
        try container.encode(expires_at, forKey: .expires_at)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(permissions, forKey: .permissions)
    }
}

/// EnrollmentToken structure matching Rust implementation exactly
public struct EnrollmentToken: Codable {
    public let body: EnrollmentTokenBody
    public let signature: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
    public let signer_id: String
    
    enum CodingKeys: String, CodingKey {
        case body
        case signature
        case signer_id
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        body = try container.decode(EnrollmentTokenBody.self, forKey: .body)
        signature = try container.decode([UInt8].self, forKey: .signature)
        signer_id = try container.decode(String.self, forKey: .signer_id)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(body, forKey: .body)
        try container.encode(signature, forKey: .signature)
        try container.encode(signer_id, forKey: .signer_id)
    }
}

// MARK: - Data Extensions

extension Data {
    public init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        for _ in 0 ..< len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i ..< j]
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
