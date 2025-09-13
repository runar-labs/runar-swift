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
