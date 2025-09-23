import CRunarFFI
import Foundation
import Darwin
import SwiftCBOR
import SwiftCommon

// MARK: - Handle Lock Registry

/// Thread-safe registry for managing locks on FFI handles
internal final class HandleLockRegistry {
    nonisolated(unsafe) static let shared = HandleLockRegistry()
    private let tableLock = NSLock()
    private var locks: [UInt: NSLock] = [:]
    
    private init() {}
    
    private func lockFor(_ rawHandle: UnsafeMutableRawPointer) -> NSLock {
        let key = UInt(bitPattern: rawHandle)
        tableLock.lock()
        defer { tableLock.unlock() }
        if let l = locks[key] { return l }
        let l = NSLock()
        locks[key] = l
        return l
    }
    
    @inline(__always)
    func withLock<T>(for rawHandle: UnsafeMutableRawPointer, _ body: () throws -> T) rethrows -> T {
        let l = lockFor(rawHandle)
        l.lock()
        defer { l.unlock() }
        return try body()
    }
}

// MARK: - Sendable Handle Wrapper

/// A thread-safe wrapper for FFI handles
struct SendableHandle: @unchecked Sendable {
    let handle: UnsafeMutableRawPointer
    
    init(_ handle: UnsafeMutableRawPointer) {
        self.handle = handle
    }
}

// MARK: - Key Manager Protocols

/// Keystore capabilities information
public struct KeystoreCapabilities: Sendable {
    public let version: UInt32
    public let flags: UInt32
}

/// Common key manager operations shared by both node and mobile managers
///
/// This protocol defines the common operations that are available to both node and mobile key managers,
/// including envelope crypto, symmetric key management, persistence, and general message crypto.
public protocol CommonKeyManager {
    // Envelope crypto (serializer-critical)
    func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profilePublicKeys: [Data]) async throws -> Data
    func decryptEnvelope(envelopeData: Data) async throws -> Data

    // Symmetric key management (default-key based)
    func ensureSymmetricKey(name: String) async throws -> Data
    func encryptLocalData(data: Data) async throws -> Data
    func decryptLocalData(encryptedData: Data) async throws -> Data

    // Persistence & keystore
    func setPersistenceDirectory(_ path: String) async throws
    func enableAutoPersistence(_ enabled: Bool) async throws
    func wipePersistence() async throws
    func getKeystoreCapabilities() async throws -> KeystoreCapabilities
    func flushState() async throws
    func registerAppleDeviceKeystore(label: String) async throws

    // General message crypto (role-agnostic FFI)
    func encryptForNetwork(data: Data, networkPublicKey: Data) async throws -> Data
    func decryptNetworkData(encryptedEnvelope: Data) async throws -> Data
}

/// Node-specific key manager operations
/// 
/// This protocol defines operations that are only available to node key managers,
/// including certificate management, profile key operations, and network key handling.
public protocol NodeOnly: CommonKeyManager {
    /// Check if node has keys generated
    /// - Returns: True if keys exist, false otherwise
    /// - Throws: FFIError if the operation fails
    func hasKeys() async throws -> Bool
    
    /// Generate keys for the node
    /// - Throws: FFIError if key generation fails
    func generateKeys() async throws
    
    /// Generate CSR setup token for certificate enrollment
    /// - Returns: CSR setup token data
    /// - Throws: FFIError if generation fails
    func generateCsrSetupToken() async throws -> Data
    
    /// Generate CSR for certificate enrollment
    /// - Returns: CSR data
    /// - Throws: FFIError if generation fails
    func generateCSR() async throws -> Data
    
    /// Install certificate from CA response
    /// - Parameter certMessage: Certificate message data
    /// - Throws: FFIError if installation fails
    func installCertificate(_ certMessage: Data) async throws
    
    /// Get QUIC certificate configuration
    /// - Returns: QUIC certificate configuration data
    /// - Throws: FFIError if the operation fails
    func getQuicCertificateConfig() async throws -> Data
    
    /// Get node certificate
    /// - Returns: Node certificate data
    /// - Throws: FFIError if the operation fails
    func getNodeCertificate() async throws -> Data
    
    /// Get node public key
    /// - Returns: Node public key data
    /// - Throws: FFIError if the operation fails
    func getNodePublicKey() async throws -> Data
    
    /// Derive user profile key for given label
    /// - Parameter label: Profile label (e.g., "personal", "work")
    /// - Returns: Derived profile key data
    /// - Throws: FFIError if derivation fails
    func deriveUserProfileKey(label: String) async throws -> Data
    
    /// Decrypt envelope data using specific profile
    /// - Parameters:
    ///   - envelopeData: Encrypted envelope data
    ///   - profileId: Profile ID to use for decryption
    /// - Returns: Decrypted data
    /// - Throws: FFIError if decryption fails
    func decryptWithProfile(envelopeData: Data, profileId: String) async throws -> Data
    
    /// Install profile public key
    /// - Parameter publicKey: Profile public key data
    /// - Throws: FFIError if installation fails
    func installProfilePublicKey(_ publicKey: Data) async throws
    
    /// Get profile public key by label
    /// - Parameter label: Profile label
    /// - Returns: Tuple containing public key data and existence flag
    /// - Throws: FFIError if the operation fails
    func getProfilePublicKey(label: String) async throws -> (publicKey: Data?, exists: Bool)
    
    /// Get certificate status
    /// - Returns: Certificate status code
    /// - Throws: FFIError if the operation fails
    func getCertificateStatus() async throws -> Int32
    
    /// Get certificate serial number
    /// - Returns: Certificate serial number string
    /// - Throws: FFIError if the operation fails
    func getCertificateSerial() async throws -> String
    
    /// Validate peer certificate
    /// - Parameter cert: Peer certificate data
    /// - Throws: FFIError if validation fails
    func validatePeerCertificate(_ cert: Data) async throws
    
    /// Install network key from message
    /// - Parameter networkKeyMessage: Network key message data
    /// - Throws: FFIError if installation fails
    func installNetworkKey(_ networkKeyMessage: Data) async throws
    
    /// Get network agreement for given network public key
    /// - Parameter networkPublicKey: Network public key
    /// - Returns: Network agreement data
    /// - Throws: FFIError if the operation fails
    func getNetworkAgreement(networkPublicKey: Data) async throws -> Data
    
    /// Check if node has network private key for given public key
    /// - Parameter networkPublicKey: Network public key to check
    /// - Returns: True if private key exists, false otherwise
    /// - Throws: FFIError if the operation fails
    func hasNetworkPrivateKey(networkPublicKey: Data) async throws -> Bool

    /// Get node agreement public key for network key exchange
    /// - Returns: The node agreement public key
    /// - Throws: FFIError if the operation fails
    func getNodeAgreementPublicKey() async throws -> Data

    /// Set local node information
    /// - Parameter nodeInfoCbor: Node information in CBOR format
    /// - Throws: FFIError if the operation fails
    func setLocalNodeInfo(_ nodeInfoCbor: Data) async throws

    /// Get agreement public key (alias for getNodeAgreementPublicKey)
    /// - Returns: The agreement public key
    /// - Throws: FFIError if the operation fails
    func getAgreementPublicKey() async throws -> Data

    // Message crypto (node <-> mobile)
    /// Encrypt message for mobile device
    /// - Parameters:
    ///   - data: Data to encrypt
    ///   - mobilePublicKey: Mobile device public key
    /// - Returns: Encrypted message data
    /// - Throws: FFIError if encryption fails
    func encryptMessageForMobile(data: Data, mobilePublicKey: Data) async throws -> Data

    /// Decrypt message from mobile device
    /// - Parameter encryptedData: Encrypted message data
    /// - Returns: Decrypted data
    /// - Throws: FFIError if decryption fails
    func decryptMessageFromMobile(encryptedData: Data) async throws -> Data
}

/// Mobile-specific key manager operations
/// 
/// This protocol defines operations that are only available to mobile key managers,
/// including user key initialization, network key exchange, and certificate processing.
public protocol MobileOnly: CommonKeyManager {
    /// Initialize user root key for mobile device
    /// - Throws: FFIError if initialization fails
    func initializeUserRootKey() async throws
    
    /// Get user public key
    /// - Returns: User public key data
    /// - Throws: FFIError if the operation fails
    func getUserPublicKey() async throws -> Data
    
    /// Derive user profile key for given label
    /// - Parameter label: Profile label (e.g., "personal", "work")
    /// - Returns: Derived profile key data
    /// - Throws: FFIError if derivation fails
    func deriveUserProfileKey(label: String) async throws -> Data
    
    /// Install network public key
    /// - Parameter networkPublicKey: Network public key data
    /// - Throws: FFIError if installation fails
    func installNetworkPublicKey(_ networkPublicKey: Data) async throws
    
    /// Generate CSR for certificate enrollment
    /// - Returns: CSR data
    /// - Throws: FFIError if generation fails
    func generateCSR() async throws -> Data
    
    /// Install certificate from CA response
    /// - Parameter certMessage: Certificate message data
    /// - Throws: FFIError if installation fails
    func installCertificate(_ certMessage: Data) async throws
    
    /// Generate network data key
    /// - Returns: Generated network data key
    /// - Throws: FFIError if generation fails
    func generateNetworkDataKey() async throws -> Data
    
    /// Check if mobile has network private key for given public key
    /// - Parameter networkPublicKey: Network public key to check
    /// - Returns: True if private key exists, false otherwise
    /// - Throws: FFIError if the operation fails
    func hasNetworkPrivateKey(networkPublicKey: Data) async throws -> Bool
    
    /// Create network key message for key exchange
    /// - Parameters:
    ///   - networkPublicKey: Network public key
    ///   - nodeAgreementPublicKey: Node agreement public key
    /// - Returns: Network key message data
    /// - Throws: FFIError if creation fails
    func createNetworkKeyMessage(networkPublicKey: Data, nodeAgreementPublicKey: Data) async throws -> Data
    
    /// Process setup token (CSR) to create certificate
    /// - Parameter setupToken: Certificate signing request data
    /// - Returns: Certificate message data
    /// - Throws: FFIError if processing fails
    func processSetupToken(_ setupToken: Data) async throws -> Data
    
    /// Process enroll response from CA
    /// - Parameter response: Enroll response data
    /// - Returns: Processed response data
    /// - Throws: FFIError if processing fails
    func fromEnrollResponse(_ response: Data) async throws -> Data
    
    /// Process renew response from CA
    /// - Parameter response: Renew response data
    /// - Returns: Processed response data
    /// - Throws: FFIError if processing fails
    func fromRenewResponse(_ response: Data) async throws -> Data

    /// Get compact ID for a public key
    /// - Parameter key: Public key data
    /// - Returns: Compact ID string
    /// - Throws: FFIError if the operation fails
    func getCompactId(for key: Data) async throws -> String

    // Message crypto (mobile <-> node)
    /// Encrypt message for node device
    /// - Parameters:
    ///   - data: Data to encrypt
    ///   - nodeAgreementPublicKey: Node agreement public key
    /// - Returns: Encrypted message data
    /// - Throws: FFIError if encryption fails
    func encryptMessageForNode(data: Data, nodeAgreementPublicKey: Data) async throws -> Data

    /// Decrypt message from node device
    /// - Parameter encryptedData: Encrypted message data
    /// - Returns: Decrypted data
    /// - Throws: FFIError if decryption fails
    func decryptMessageFromNode(encryptedData: Data) async throws -> Data
}

// MARK: - FFI Error Types

/// Errors that can occur during FFI operations
/// 
/// This enum provides typed error handling for all FFI operations, ensuring
/// that errors from the Rust layer are properly propagated to Swift callers.
/// All errors include descriptive messages to aid in debugging.
public enum FFIError: Error, LocalizedError {
    /// An operation failed with the specified message
    /// - Parameter message: Description of what failed
    case operationFailed(String)
    
    /// An invalid parameter was provided
    /// - Parameter message: Description of the invalid parameter
    case invalidParameter(String)
    
    /// A memory-related error occurred
    /// - Parameter message: Description of the memory error
    case memoryError(String)
    
    /// A network-related error occurred
    /// - Parameter message: Description of the network error
    case networkError(String)
    
    /// Human-readable description of the error
    public var errorDescription: String? {
        switch self {
        case let .operationFailed(message):
            return "Operation failed: \(message)"
        case let .invalidParameter(message):
            return "Invalid parameter: \(message)"
        case let .memoryError(message):
            return "Memory error: \(message)"
        case let .networkError(message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - FFI Logger

/// Logger for FFI operations
/// 
/// Provides logging functionality that integrates with the Rust FFI layer.
/// This class allows setting log levels and node context for debugging FFI operations.
/// 
/// - Note: This logger integrates with SwiftCommon's RunarLogger for actual output.
public class FFILogger {
    /// Available log levels for FFI operations
    public enum LogLevel: Int32, CaseIterable {
        /// No logging
        case off = 0
        /// Error level logging
        case error = 1
        /// Warning level logging
        case warn = 2
        /// Info level logging
        case info = 3
        /// Debug level logging
        case debug = 4
        /// Trace level logging
        case trace = 5
        
        /// String representation of the log level
        public var stringValue: String {
            switch self {
            case .off: return "OFF"
            case .error: return "ERROR"
            case .warn: return "WARN"
            case .info: return "INFO"
            case .debug: return "DEBUG"
            case .trace: return "TRACE"
            }
        }
    }
    
    /// Set the global log level for the Rust FFI logger
    /// - Parameter level: The log level to set
    /// - Throws: FFIError if the operation fails
    public static func setLogLevel(_ level: LogLevel) async throws {
        let (code, error) = withRnError { errPtr in
            rn_set_log_level(level.rawValue, errPtr)
        }
        if let error = error { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to set log level (code: \(code))") }
    }
    
    /// Set the node ID for the Rust FFI logger context
    /// - Parameter nodeId: The node ID to set for logging context
    /// - Throws: FFIError if the operation fails
    public static func setLoggerNodeId(_ nodeId: String) async throws {
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
    public static func log(_: LogLevel, _: String) {
        // The actual logging is handled by the Rust side through the log level setting
        // This method is provided for API consistency but relies on SwiftCommon's RunarLogger
        // in the calling code for actual output
    }
}

// MARK: - Input Validation and Security

/// Validates that a data parameter is not empty for functions that require non-empty data
/// - Parameter data: The data to validate
/// - Parameter parameterName: The name of the parameter for error messages
/// - Throws: FFIError.invalidParameter if data is empty
private func validateNonEmptyData(_ data: Data, parameterName: String) async throws {
    guard !data.isEmpty else {
        throw FFIError.invalidParameter("\(parameterName) cannot be empty")
    }
}

/// Validates that a string parameter is not empty
/// - Parameter string: The string to validate
/// - Parameter parameterName: The name of the parameter for error messages
/// - Throws: FFIError.invalidParameter if string is empty
private func validateNonEmptyString(_ string: String, parameterName: String) async throws {
    guard !string.isEmpty else {
        throw FFIError.invalidParameter("\(parameterName) cannot be empty")
    }
}

/// Validates that a string parameter is not empty and not too long
/// - Parameter string: The string to validate
/// - Parameter parameterName: The name of the parameter for error messages
/// - Parameter maxLength: Maximum allowed length (default: 1024)
/// - Throws: FFIError.invalidParameter if string is empty or too long
private func validateStringLength(_ string: String, parameterName: String, maxLength: Int = 1024) async throws {
    try await validateNonEmptyString(string, parameterName: parameterName)
    guard string.count <= maxLength else {
        throw FFIError.invalidParameter("\(parameterName) cannot exceed \(maxLength) characters")
    }
}

/// Validates that a data parameter is not empty and not too large
/// - Parameter data: The data to validate
/// - Parameter parameterName: The name of the parameter for error messages
/// - Parameter maxSize: Maximum allowed size in bytes (default: 10MB)
/// - Throws: FFIError.invalidParameter if data is empty or too large
private func validateDataSize(_ data: Data, parameterName: String, maxSize: Int = 10 * 1024 * 1024) async throws {
    try await validateNonEmptyData(data, parameterName: parameterName)
    guard data.count <= maxSize else {
        throw FFIError.invalidParameter("\(parameterName) cannot exceed \(maxSize) bytes")
    }
}

/// Validates that a handle is not nil
/// - Parameter handle: The handle to validate
/// - Parameter parameterName: The name of the parameter for error messages
/// - Throws: FFIError.invalidParameter if handle is nil
private func validateHandle<T>(_ handle: T?, parameterName: String) async throws {
    guard handle != nil else {
        throw FFIError.invalidParameter("\(parameterName) cannot be nil")
    }
}

/// Validates that an array is not empty
/// - Parameter array: The array to validate
/// - Parameter parameterName: The name of the parameter for error messages
/// - Throws: FFIError.invalidParameter if array is empty
private func validateNonEmptyArray<T>(_ array: [T], parameterName: String) async throws {
    guard !array.isEmpty else {
        throw FFIError.invalidParameter("\(parameterName) cannot be empty")
    }
}

// MARK: - FFI Helper Functions

@inline(__always)
private func buildError(from err: CRunarFFI.RnError) -> Error {
    if let msgPtr = err.message {
        let message = String(cString: msgPtr)
        return FFIError.operationFailed(message)
    }
    return FFIError.operationFailed("Unknown FFI error")
}

@inline(__always)
func withRnErrorCode(_ body: (UnsafeMutablePointer<CRunarFFI.RnError>) -> Int32) -> (Int32, Error?) {
    var err = CRunarFFI.RnError(code: 0, message: nil)
    let code = withUnsafeMutablePointer(to: &err) { errPtr in
        body(errPtr)
    }
    if code != 0 {
        // Copy error message (if any) and immediately free it at the FFI layer
        var errorMessage: String?
        if err.message != nil {
            errorMessage = String(cString: err.message!)
            // Free and null the message via centralized API
            withUnsafeMutablePointer(to: &err) { errPtr in
                rn_error_free(errPtr)
            }
        }
        let swiftError = FFIError.operationFailed(errorMessage ?? "Unknown FFI error")
        return (code, swiftError)
    }
    return (code, nil)
}

@inline(__always)
public func withRnError(_ body: (UnsafeMutablePointer<CRunarFFI.RnError>) -> Int32) -> (Int32, Error?) {
    return withRnErrorCode(body)
}

// MARK: - Nonisolated FFI Helper Functions

/// Nonisolated helper for encrypting with envelope (node)
@inline(__always)
internal func ffi_node_encrypt_with_envelope(
    _ handle: UnsafeMutableRawPointer,
    data: Data,
    networkPublicKey: Data?,
    profilePublicKeys: [Data]
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            data.withUnsafeBytes { dataRaw in
                var keyPointers: [UnsafePointer<UInt8>?] = []
                var keyLengths: [Int] = []
                keyPointers.reserveCapacity(profilePublicKeys.count)
                keyLengths.reserveCapacity(profilePublicKeys.count)
                for key in profilePublicKeys {
                    key.withUnsafeBytes { keyRaw in
                        keyPointers.append(keyRaw.bindMemory(to: UInt8.self).baseAddress)
                        keyLengths.append(key.count)
                    }
                }
                return keyPointers.withUnsafeBufferPointer { keysPtr in
                    keyLengths.withUnsafeBufferPointer { lensPtr in
                        if let networkKey = networkPublicKey {
                            networkKey.withUnsafeBytes { networkRaw in
                                rn_keys_node_encrypt_with_envelope(
                                    nodeHandle,
                                    dataRaw.bindMemory(to: UInt8.self).baseAddress,
                                    data.count,
                                    networkRaw.bindMemory(to: UInt8.self).baseAddress,
                                    networkKey.count,
                                    keysPtr.baseAddress,
                                    lensPtr.baseAddress,
                                    profilePublicKeys.count,
                                    &outPtr,
                                    &outLen,
                                    errPtr
                                )
                            }
                        } else {
                            rn_keys_node_encrypt_with_envelope(
                                nodeHandle,
                                dataRaw.bindMemory(to: UInt8.self).baseAddress,
                                data.count,
                                nil,
                                0,
                                keysPtr.baseAddress,
                                lensPtr.baseAddress,
                                profilePublicKeys.count,
                                &outPtr,
                                &outLen,
                                errPtr
                            )
                        }
                    }
                }
            }
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to encrypt with envelope") }
    return try copyBytesAndFree(outPtr, outLen)
}

@inline(__always)
internal func ffi_mobile_encrypt_with_envelope(
    _ handle: UnsafeMutableRawPointer,
    data: Data,
    networkPublicKey: Data?,
    profilePublicKeys: [Data]
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let mobileHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: mobileHandle) {
            data.withUnsafeBytes { dataRaw in
                var keyPointers: [UnsafePointer<UInt8>?] = []
                var keyLengths: [Int] = []
                keyPointers.reserveCapacity(profilePublicKeys.count)
                keyLengths.reserveCapacity(profilePublicKeys.count)
                for key in profilePublicKeys {
                    key.withUnsafeBytes { keyRaw in
                        keyPointers.append(keyRaw.bindMemory(to: UInt8.self).baseAddress)
                        keyLengths.append(key.count)
                    }
                }
                return keyPointers.withUnsafeBufferPointer { keysPtr in
                    keyLengths.withUnsafeBufferPointer { lensPtr in
                        if let networkKey = networkPublicKey {
                            networkKey.withUnsafeBytes { networkRaw in
                                rn_keys_mobile_encrypt_with_envelope(
                                    mobileHandle,
                                    dataRaw.bindMemory(to: UInt8.self).baseAddress,
                                    data.count,
                                    networkRaw.bindMemory(to: UInt8.self).baseAddress,
                                    networkKey.count,
                                    keysPtr.baseAddress,
                                    lensPtr.baseAddress,
                                    profilePublicKeys.count,
                                    &outPtr,
                                    &outLen,
                                    errPtr
                                )
                            }
                        } else {
                            rn_keys_mobile_encrypt_with_envelope(
                                mobileHandle,
                                dataRaw.bindMemory(to: UInt8.self).baseAddress,
                                data.count,
                                nil,
                                0,
                                keysPtr.baseAddress,
                                lensPtr.baseAddress,
                                profilePublicKeys.count,
                                &outPtr,
                                &outLen,
                                errPtr
                            )
                        }
                    }
                }
            }
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to encrypt with envelope") }
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for decrypting envelope (node)
@inline(__always)
internal func ffi_node_decrypt_envelope(
    _ handle: UnsafeMutableRawPointer,
    envelopeData: Data
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            envelopeData.withUnsafeBytes { raw in
                rn_keys_node_decrypt_envelope(nodeHandle, raw.bindMemory(to: UInt8.self).baseAddress, envelopeData.count, &outPtr, &outLen, errPtr)
            }
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to decrypt envelope") }
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for generating CSR setup token (node)
@inline(__always)
internal func ffi_node_generate_csr(
    _ handle: UnsafeMutableRawPointer
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    let logger = RunarLogger(component: .custom)
    let threadId = pthread_mach_thread_np(pthread_self())
    logger.trace("ffi_node_generate_csr: ENTER thread=\(threadId) nodeHandle=\(nodeHandle)")
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            rn_keys_node_generate_csr(nodeHandle, &outPtr, &outLen, errPtr)
        }
    }
    
    if let error = err {
        logger.trace("ffi_node_generate_csr: ERROR thread=\(threadId) nodeHandle=\(nodeHandle) code=\(code) err=\(error)")
        throw error
    }
    guard code == 0 else { throw FFIError.operationFailed("Failed to generate CSR setup token") }
    logger.trace("ffi_node_generate_csr: SUCCESS thread=\(threadId) nodeHandle=\(nodeHandle) outPtr=\(String(describing: outPtr)) outLen=\(outLen)")
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for getting QUIC certificate config (node)
@inline(__always)
internal func ffi_node_get_quic_certificate_config(
    _ handle: UnsafeMutableRawPointer
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            rn_keys_node_get_quic_certificate_config(nodeHandle, &outPtr, &outLen, errPtr)
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to get QUIC certificate config") }
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for getting node certificate (node)
@inline(__always)
internal func ffi_node_get_node_certificate(
    _ handle: UnsafeMutableRawPointer
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            rn_keys_node_get_node_certificate(nodeHandle, &outPtr, &outLen, errPtr)
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to get node certificate") }
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for getting node public key (node)
@inline(__always)
internal func ffi_node_get_public_key(
    _ handle: UnsafeMutableRawPointer
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            rn_keys_node_get_public_key(nodeHandle, &outPtr, &outLen, errPtr)
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to get node public key") }
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for deriving user profile key (node)
@inline(__always)
internal func ffi_node_derive_user_profile_key(
    _ handle: UnsafeMutableRawPointer,
    label: String
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            label.withCString { cLabel in
                rn_keys_node_derive_user_profile_key(nodeHandle, cLabel, &outPtr, &outLen, errPtr)
            }
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to derive user profile key") }
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for decrypting with profile (node)
@inline(__always)
internal func ffi_node_decrypt_with_profile(
    _ handle: UnsafeMutableRawPointer,
    envelopeData: Data,
    profileId: String
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            envelopeData.withUnsafeBytes { raw in
                profileId.withCString { cId in
                    rn_keys_node_decrypt_with_profile(
                        nodeHandle,
                        raw.bindMemory(to: UInt8.self).baseAddress,
                        envelopeData.count,
                        cId,
                        &outPtr,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to decrypt with profile") }
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for getting profile public key by label (node)
@inline(__always)
internal func ffi_node_get_profile_public_key_by_label(
    _ handle: UnsafeMutableRawPointer,
    label: String
) throws -> (publicKey: Data?, exists: Bool) {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    var hasKey: Int32 = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            label.withCString { cLabel in
                rn_keys_node_get_profile_public_key_by_label(nodeHandle, cLabel, &outPtr, &outLen, &hasKey, errPtr)
            }
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to get profile public key") }
    
    if hasKey == 0 {
        return (nil, false)
    }
    
    let publicKey = try copyBytesAndFree(outPtr, outLen)
    return (publicKey, true)
}

/// Nonisolated helper for getting certificate serial (node)
@inline(__always)
internal func ffi_node_get_certificate_serial(
    _ handle: UnsafeMutableRawPointer
) throws -> String {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<CChar>?
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            rn_keys_node_get_certificate_serial(nodeHandle, &outPtr, errPtr)
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to get certificate serial") }
    return try copyCStringAndFree(outPtr)
}

/// Nonisolated helper for getting network agreement (node)
@inline(__always)
internal func ffi_node_get_network_agreement(
    _ handle: UnsafeMutableRawPointer,
    networkPublicKey: Data
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            networkPublicKey.withUnsafeBytes { raw in
                rn_keys_node_get_network_agreement(nodeHandle, raw.bindMemory(to: UInt8.self).baseAddress, networkPublicKey.count, &outPtr, &outLen, errPtr)
            }
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to get network agreement") }
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for getting agreement public key (node)
@inline(__always)
internal func ffi_node_get_agreement_public_key(
    _ handle: UnsafeMutableRawPointer
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            rn_keys_node_get_agreement_public_key(nodeHandle, &outPtr, &outLen, errPtr)
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to get node agreement public key") }
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for ensuring symmetric key (common)
@inline(__always)
internal func ffi_ensure_symmetric_key(
    _ handle: UnsafeMutableRawPointer,
    name: String
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            name.withCString { namePtr in
                rn_keys_ensure_symmetric_key(nodeHandle, namePtr, &outPtr, &outLen, errPtr)
            }
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to ensure symmetric key") }
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for encrypting local data (common)
@inline(__always)
internal func ffi_encrypt_local_data(
    _ handle: UnsafeMutableRawPointer,
    data: Data
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            data.withUnsafeBytes { dataRaw in
                rn_keys_encrypt_local_data(nodeHandle, dataRaw.bindMemory(to: UInt8.self).baseAddress, data.count, &outPtr, &outLen, errPtr)
            }
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to encrypt local data") }
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for decrypting local data (common)
@inline(__always)
internal func ffi_decrypt_local_data(
    _ handle: UnsafeMutableRawPointer,
    encryptedData: Data
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            encryptedData.withUnsafeBytes { dataRaw in
                rn_keys_decrypt_local_data(nodeHandle, dataRaw.bindMemory(to: UInt8.self).baseAddress, encryptedData.count, &outPtr, &outLen, errPtr)
            }
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to decrypt local data") }
    return try copyBytesAndFree(outPtr, outLen)
}


/// Nonisolated helper for encrypting for network (common)
@inline(__always)
internal func ffi_encrypt_for_network(
    _ handle: UnsafeMutableRawPointer,
    data: Data,
    networkPublicKey: Data
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            data.withUnsafeBytes { dataRaw in
                networkPublicKey.withUnsafeBytes { keyRaw in
                    rn_keys_encrypt_for_network(nodeHandle, dataRaw.bindMemory(to: UInt8.self).baseAddress, data.count, keyRaw.bindMemory(to: UInt8.self).baseAddress, networkPublicKey.count, &outPtr, &outLen, errPtr)
                }
            }
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to encrypt for network") }
    return try copyBytesAndFree(outPtr, outLen)
}

/// Nonisolated helper for decrypting network data (common)
@inline(__always)
internal func ffi_decrypt_network_data(
    _ handle: UnsafeMutableRawPointer,
    encryptedEnvelope: Data
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            encryptedEnvelope.withUnsafeBytes { dataRaw in
                rn_keys_decrypt_network_data(nodeHandle, dataRaw.bindMemory(to: UInt8.self).baseAddress, encryptedEnvelope.count, &outPtr, &outLen, errPtr)
            }
        }
    }
    
    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to decrypt network data") }
    return try copyBytesAndFree(outPtr, outLen)
}

// MARK: - Additional Helper Functions for Mobile Key Manager

@inline(__always)
internal func ffi_mobile_get_user_public_key(
    _ handle: UnsafeMutableRawPointer
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let mobileHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: mobileHandle) {
            rn_keys_mobile_get_user_public_key(mobileHandle, &outPtr, &outLen, errPtr)
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to get user public key") }
    return try copyBytesAndFree(outPtr, outLen)
}

@inline(__always)
internal func ffi_mobile_derive_user_profile_key(
    _ handle: UnsafeMutableRawPointer,
    label: String
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let mobileHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: mobileHandle) {
            label.withCString { cLabel in
                rn_keys_mobile_derive_user_profile_key(mobileHandle, cLabel, &outPtr, &outLen, errPtr)
            }
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to derive user profile key") }
    return try copyBytesAndFree(outPtr, outLen)
}

@inline(__always)
internal func ffi_mobile_generate_network_data_key(
    _ handle: UnsafeMutableRawPointer
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let mobileHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: mobileHandle) {
            rn_keys_mobile_generate_network_data_key(mobileHandle, &outPtr, &outLen, errPtr)
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to generate network data key") }
    return try copyBytesAndFree(outPtr, outLen)
}

@inline(__always)
internal func ffi_mobile_create_network_key_message(
    _ handle: UnsafeMutableRawPointer,
    data: Data,
    nodeAgreementPublicKey: Data
) throws -> Data {
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: handle) {
            data.withUnsafeBytes { dataRaw in
                nodeAgreementPublicKey.withUnsafeBytes { nodeRaw in
                    rn_keys_mobile_create_network_key_message(
                        handle,
                        dataRaw.bindMemory(to: UInt8.self).baseAddress,
                        data.count,
                        nodeRaw.bindMemory(to: UInt8.self).baseAddress,
                        nodeAgreementPublicKey.count,
                        &outPtr,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to create network key message") }
    return try copyBytesAndFree(outPtr, outLen)
}

@inline(__always)
internal func ffi_mobile_process_setup_token(
    _ handle: UnsafeMutableRawPointer,
    setupToken: Data
) throws -> Data {
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: handle) {
            setupToken.withUnsafeBytes { raw in
                rn_keys_mobile_process_setup_token(
                    handle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    setupToken.count,
                    &outPtr,
                    &outLen,
                    errPtr
                )
            }
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to process setup token") }
    return try copyBytesAndFree(outPtr, outLen)
}

@inline(__always)
internal func ffi_mobile_from_enroll_response(
    _ handle: UnsafeMutableRawPointer,
    response: Data
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let mobileHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: mobileHandle) {
            response.withUnsafeBytes { raw in
                rn_keys_mobile_from_enroll_response(mobileHandle, raw.bindMemory(to: UInt8.self).baseAddress, response.count, &outPtr, &outLen, errPtr)
            }
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to convert enroll response") }
    return try copyBytesAndFree(outPtr, outLen)
}

@inline(__always)
internal func ffi_mobile_from_renew_response(
    _ handle: UnsafeMutableRawPointer,
    response: Data
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let mobileHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: mobileHandle) {
            response.withUnsafeBytes { raw in
                rn_keys_mobile_from_renew_response(mobileHandle, raw.bindMemory(to: UInt8.self).baseAddress, response.count, &outPtr, &outLen, errPtr)
            }
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to convert renew response") }
    return try copyBytesAndFree(outPtr, outLen)
}

// MARK: - Additional Helper Functions for Message Encryption

@inline(__always)
internal func ffi_encrypt_message_for_mobile(
    _ handle: UnsafeMutableRawPointer,
    data: Data,
    mobilePublicKey: Data
) throws -> Data {
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: handle) {
            data.withUnsafeBytes { dataRaw in
                mobilePublicKey.withUnsafeBytes { keyRaw in
                    rn_keys_encrypt_message_for_mobile(handle, dataRaw.bindMemory(to: UInt8.self).baseAddress, data.count, keyRaw.bindMemory(to: UInt8.self).baseAddress, mobilePublicKey.count, &outPtr, &outLen, errPtr)
                }
            }
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to encrypt message for mobile") }
    return try copyBytesAndFree(outPtr, outLen)
}

@inline(__always)
internal func ffi_decrypt_message_from_mobile(
    _ handle: UnsafeMutableRawPointer,
    encryptedData: Data
) throws -> Data {
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: handle) {
            encryptedData.withUnsafeBytes { dataRaw in
                rn_keys_decrypt_message_from_mobile(handle, dataRaw.bindMemory(to: UInt8.self).baseAddress, encryptedData.count, &outPtr, &outLen, errPtr)
            }
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to decrypt message from mobile") }
    return try copyBytesAndFree(outPtr, outLen)
}

@inline(__always)
internal func ffi_encrypt_message_for_node(
    _ handle: UnsafeMutableRawPointer,
    data: Data,
    nodeAgreementPublicKey: Data
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let mobileHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: mobileHandle) {
            data.withUnsafeBytes { dataRaw in
                nodeAgreementPublicKey.withUnsafeBytes { keyRaw in
                    rn_keys_encrypt_message_for_node(mobileHandle, dataRaw.bindMemory(to: UInt8.self).baseAddress, data.count, keyRaw.bindMemory(to: UInt8.self).baseAddress, nodeAgreementPublicKey.count, &outPtr, &outLen, errPtr)
                }
            }
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to encrypt message for node") }
    return try copyBytesAndFree(outPtr, outLen)
}

@inline(__always)
internal func ffi_mobile_decrypt_message_from_node(
    _ handle: UnsafeMutableRawPointer,
    encryptedData: Data
) throws -> Data {
    // Copy handle to local to avoid capturing actor state in closures
    let mobileHandle = handle
    var outPtr: UnsafeMutablePointer<UInt8>?
    var outLen = 0

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: mobileHandle) {
            encryptedData.withUnsafeBytes { dataRaw in
                rn_keys_mobile_decrypt_message_from_node(mobileHandle, dataRaw.bindMemory(to: UInt8.self).baseAddress, encryptedData.count, &outPtr, &outLen, errPtr)
            }
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to decrypt message from node") }
    return try copyBytesAndFree(outPtr, outLen)
}

// MARK: - Additional Helper Functions for Transport and CA

@inline(__always)
internal func ffi_create_ca_client(
    _ handle: UnsafeMutableRawPointer,
    configCbor: Data
) throws -> UnsafeMutableRawPointer {
    let logger = RunarLogger(component: .custom)
    logger.info("ffi_create_ca_client() - Creating CA client")
    logger.debug("ffi_create_ca_client() - Config CBOR length: \(configCbor.count)")
    
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var out: UnsafeMutableRawPointer?
    
    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            configCbor.withUnsafeBytes { raw in
                logger.trace("ffi_create_ca_client() - About to call rn_transport_ca_client_new_with_config")
                return rn_transport_ca_client_new_with_config(raw.bindMemory(to: UInt8.self).baseAddress, configCbor.count, nodeHandle, &out, errPtr)
            }
        }
    }
    
    logger.debug("ffi_create_ca_client() - FFI call completed, code: \(code)")
    if let error = err { 
        logger.error("ffi_create_ca_client() - FFI error: \(error)")
        throw error 
    }
    guard code == 0, let clientHandle = out else { 
        logger.error("ffi_create_ca_client() - FFI operation failed with code: \(code)")
        throw FFIError.operationFailed("Failed to create CA client") 
    }
    logger.info("ffi_create_ca_client() - CA client created successfully")
    return clientHandle
}

@inline(__always)
internal func ffi_create_discovery(
    _ handle: UnsafeMutableRawPointer,
    optionsCbor: Data
) throws -> UnsafeMutableRawPointer {
    var outPtr: UnsafeMutableRawPointer?

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: handle) {
            optionsCbor.withUnsafeBytes { raw in
                rn_discovery_new_with_multicast(
                    handle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    optionsCbor.count,
                    &outPtr,
                    errPtr
                )
            }
        }
    }

    if let error = err { throw error }
    guard code == 0 else { throw FFIError.operationFailed("Failed to create discovery") }
    guard let discoveryHandle = outPtr else { throw FFIError.operationFailed("Discovery handle is null") }
    return discoveryHandle
}

@inline(__always)
internal func ffi_create_transport(
    _ handle: UnsafeMutableRawPointer,
    optionsCbor: Data
) throws -> UnsafeMutableRawPointer {
    // Copy handle to local to avoid capturing actor state in closures
    let nodeHandle = handle
    var outTransport: UnsafeMutableRawPointer?

    let (code, err) = withRnErrorCode { errPtr in
        HandleLockRegistry.shared.withLock(for: nodeHandle) {
            optionsCbor.withUnsafeBytes { raw in
                rn_transport_new_with_keys(nodeHandle, raw.bindMemory(to: UInt8.self).baseAddress, optionsCbor.count, &outTransport, errPtr)
            }
        }
    }

    if let error = err { throw error }
    guard code == 0, let transportHandle = outTransport else { 
        throw FFIError.operationFailed("Failed to create transport") 
    }
    return transportHandle
}

// MARK: - Additional Helper Functions for CBOR Encoding

@inline(__always)
internal func ffi_encode_ca_client_config(
    _ config: CaClientConfigAll
) async throws -> Data {
    // This is a nonisolated helper that can be called from any context
    return try await CBORHelper.encodeCaClientConfig(config)
}

// MARK: - Copy-and-free helpers for FFI outputs

@inline(__always)
private func copyBytesAndFree(_ pointer: UnsafeMutablePointer<UInt8>?, _ length: Int) throws -> Data {
    guard let pointer = pointer, length >= 0 else {
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
        var currentIndex = hexString.startIndex
        for _ in 0 ..< len {
            let nextIndex = hexString.index(currentIndex, offsetBy: 2)
            let bytes = hexString[currentIndex ..< nextIndex]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            currentIndex = nextIndex
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
    public let node_public_key: [UInt8]
    public let node_agreement_public_key: [UInt8]
    public let csr_der: [UInt8]
    
    enum CodingKeys: String, CodingKey {
        case node_id
        case node_public_key
        case node_agreement_public_key
        case csr_der
    }

    public init(node_id: String, node_public_key: [UInt8], node_agreement_public_key: [UInt8], csr_der: [UInt8]) {
        self.node_id = node_id
        self.node_public_key = node_public_key
        self.node_agreement_public_key = node_agreement_public_key
        self.csr_der = csr_der
    }

    public init(from cbor: CBOR) throws {
        guard case .map(let map) = cbor else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Expected CBOR map"))
        }
        
        // Extract node_id
        guard let nodeIdCbor = map[CBOR.utf8String("node_id")],
              case .utf8String(let nodeId) = nodeIdCbor else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Missing or invalid node_id"))
        }
        self.node_id = nodeId
        
        // Extract node_public_key (CBOR array of bytes)
        guard let nodePublicKeyCbor = map[CBOR.utf8String("node_public_key")],
              case .array(let nodePublicKeyArray) = nodePublicKeyCbor else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Missing or invalid node_public_key"))
        }
        self.node_public_key = try nodePublicKeyArray.map { byteCbor in
            guard case .unsignedInt(let byte) = byteCbor else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid byte in node_public_key array"))
            }
            return UInt8(byte)
        }
        
        // Extract node_agreement_public_key (CBOR array of bytes)
        guard let nodeAgreementPublicKeyCbor = map[CBOR.utf8String("node_agreement_public_key")],
              case .array(let nodeAgreementPublicKeyArray) = nodeAgreementPublicKeyCbor else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Missing or invalid node_agreement_public_key"))
        }
        self.node_agreement_public_key = try nodeAgreementPublicKeyArray.map { byteCbor in
            guard case .unsignedInt(let byte) = byteCbor else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid byte in node_agreement_public_key array"))
            }
            return UInt8(byte)
        }
        
        // Extract csr_der (CBOR array of bytes)
        guard let csrDerCbor = map[CBOR.utf8String("csr_der")],
              case .array(let csrDerArray) = csrDerCbor else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Missing or invalid csr_der"))
        }
        self.csr_der = try csrDerArray.map { byteCbor in
            guard case .unsignedInt(let byte) = byteCbor else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid byte in csr_der array"))
            }
            return UInt8(byte)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        node_id = try container.decode(String.self, forKey: .node_id)
        
        // Decode binary fields as [UInt8] directly from CBOR arrays
        node_public_key = try container.decode([UInt8].self, forKey: .node_public_key)
        node_agreement_public_key = try container.decode([UInt8].self, forKey: .node_agreement_public_key)
        csr_der = try container.decode([UInt8].self, forKey: .csr_der)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(node_id, forKey: .node_id)
        try container.encode(node_public_key, forKey: .node_public_key)
        try container.encode(node_agreement_public_key, forKey: .node_agreement_public_key)
        try container.encode(csr_der, forKey: .csr_der)
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

public struct CsrEnrollResponse: Codable {
    public let network_id: String
    public let certificate_der: [UInt8]
    public let issuing_ca_der: [UInt8]
    public let root_ca_der: [UInt8]?
    public let expires_at: UInt64
    
    enum CodingKeys: String, CodingKey {
        case network_id
        case certificate_der
        case issuing_ca_der
        case root_ca_der
        case expires_at
    }
}

public struct CaErrorResponse: Codable {
    public let code: String
    public let message: String
    public let reason: String?
    
    enum CodingKeys: String, CodingKey {
        case code
        case message
        case reason
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

/// Revocation response structure
public struct RevokeResponse: Codable {
    public let ok: Bool
    
    enum CodingKeys: String, CodingKey {
        case ok
    }
}

/// CRL-lite structure
public struct CrlLite: Codable {
    public let network_id: String
    public let revoked_serials: [[UInt8]]
    public let signature: Data
    public let issuing_ca_serial_hex: String
    
    enum CodingKeys: String, CodingKey {
        case network_id
        case revoked_serials
        case signature
        case issuing_ca_serial_hex
    }
}

/// CA Status structure
public struct CaStatus: Codable {
    public let issuing_subject: String
    public let issuing_serial_hex: String
    public let not_before: UInt64
    public let not_after: UInt64
    
    enum CodingKeys: String, CodingKey {
        case issuing_subject
        case issuing_serial_hex
        case not_before
        case not_after
    }
}

/// Certificate chain structure
public struct CertificateChain: Codable {
    public let certificates: [Data]
    
    enum CodingKeys: String, CodingKey {
        case certificates
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

public struct CaClientConfigAll: Codable, Sendable {
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
                issuing_ca_der: Data) throws
    {
        // Validate non-empty certificates as per design requirements
        guard !root_ca_der.isEmpty else {
            throw FFIError.invalidParameter("root_ca_der cannot be empty")
        }
        guard !issuing_ca_der.isEmpty else {
            throw FFIError.invalidParameter("issuing_ca_der cannot be empty")
        }
        
        self.bootstrap_server = bootstrap_server
        self.authenticated_server = authenticated_server
        self.network_id = network_id
        self.request_timeout_seconds = request_timeout_seconds
        self.max_retries = max_retries
        self.root_ca_der = root_ca_der
        self.issuing_ca_der = issuing_ca_der
    }

    public init(from decoder: Decoder) async throws {
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

    public func encode(to encoder: Encoder) async throws {
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
                rateLimitPerHour: Int)
    {
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
    
    public init(logger _: RunarLogger) {}
    
    public func createKeyPair() async throws -> UnsafeMutableRawPointer {
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
    
    public func getPublicKey(_ handle: UnsafeMutableRawPointer) async throws -> Data {
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
    
    public func generateEnrollmentToken(params: EnrollmentTokenParams) async throws -> Data {
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
        for (index, ptr) in capabilityCStringPtrs.enumerated() {
            capsBuffer[index] = UnsafePointer(ptr)
        }

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
    public nonisolated(unsafe) let ffiHandle: UnsafeMutableRawPointer
    nonisolated(unsafe) private let _ffiHandle: UnsafeMutableRawPointer
    
    public init(ffiHandle: UnsafeMutableRawPointer) {
        self.ffiHandle = ffiHandle
        self._ffiHandle = ffiHandle
    }
    
    public nonisolated static func create() throws -> CANode {
        let logger = RunarLogger(component: .custom)
        logger.info("CANode.create() - Starting CA Node creation")
        var handle: UnsafeMutableRawPointer?
        logger.trace("CANode.create() - About to call rn_keys_ca_node_new_shared")
        let (code, err) = withRnErrorCode { errPtr in
            logger.trace("CANode.create() - Inside withRnErrorCode closure")
            let result = rn_keys_ca_node_new_shared(&handle, errPtr)
            logger.debug("CANode.create() - rn_keys_ca_node_new_shared returned: \(result)")
            return result
        }
        logger.debug("CANode.create() - withRnErrorCode completed, code: \(code)")
        if let error = err { 
        logger.error("CANode.create() - FFI error: \(error)")
        throw error
        }
        guard code == 0, let out = handle else {
            logger.error("CANode.create() - FFI operation failed with code: \(code), handle: \(handle != nil ? "non-nil" : "nil")")
            throw FFIError.operationFailed("Failed to create CA Node")
        }
        logger.info("CANode.create() - CA Node created successfully")
        return CANode(ffiHandle: out)
    }
    
    public nonisolated func setupComplete(params: CANodeManager.CANodeSetupParams) async throws {
        let logger = RunarLogger(component: .custom)
        logger.info("CANode.setupComplete() - Starting setup with params")
        logger.debug("CANode.setupComplete() - Root CA Subject: \(params.rootCaSubject)")
        logger.debug("CANode.setupComplete() - Issuing CA Subject: \(params.issuingCaSubject)")
        logger.debug("CANode.setupComplete() - Validity Days: \(params.validityDays)")
        logger.debug("CANode.setupComplete() - Issuing CA Serial: \(params.issuingCaSerial)")
        logger.debug("CANode.setupComplete() - EA Public Keys Length: \(params.eaPublicKeys.count)")
        logger.debug("CANode.setupComplete() - EA Public Keys first 20 bytes: \(Array(params.eaPublicKeys.prefix(20)))")
        logger.debug("CANode.setupComplete() - Network ID: \(params.networkId)")
        
        // Copy handle to local to avoid capturing actor state in closures
        let caHandle = self.ffiHandle
        let (code, err) = withRnErrorCode { errPtr in
            params.rootCaSubject.withCString { cRoot in
                params.issuingCaSubject.withCString { cIssuing in
                    params.networkId.withCString { cNetworkId in
                        params.eaPublicKeys.withUnsafeBytes { raw in
                            rn_keys_ca_node_setup_complete(
                                caHandle,
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
        if let error = err { 
            logger.error("CANode.setupComplete() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("CANode.setupComplete() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to setup CA Node") 
        }
        logger.info("CANode.setupComplete() - Setup completed successfully")
    }
    
    public static func freeShared(_ handle: UnsafeMutableRawPointer) {
        rn_keys_ca_node_free_shared(handle)
    }

    /// Add admin SKI to CA Node
    public nonisolated func addAdminSki(_ ski: Data) async throws {
        let caHandle = self.ffiHandle
        let skiString = String(data: ski, encoding: .utf8) ?? ""
        let (code, err) = withRnErrorCode { errPtr in
            skiString.withCString { cSki in
                rn_keys_ca_node_add_admin_ski(caHandle, cSki, errPtr)
            }
        }
        
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to add admin SKI") }
    }

    deinit {
        rn_keys_ca_node_free_shared(_ffiHandle)
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
    private nonisolated(unsafe) var handle: UnsafeMutableRawPointer?
    nonisolated(unsafe) private var _handle: UnsafeMutableRawPointer?
    
    public init(handle: UnsafeMutableRawPointer) {
        self.handle = handle
        self._handle = handle
    }
    
    public nonisolated static func create(config: CaServerConfig, sharedCaNode: UnsafeMutableRawPointer) throws -> CAServer {
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
    
    public nonisolated func stop() async throws {
        guard let server = handle else { return }
        // Copy handle to local to avoid capturing actor state in closures
        let serverHandle = server
        let (code, err) = withRnErrorCode { errPtr in
            rn_transport_ca_server_stop(serverHandle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to stop CA Server") }
    }

    public nonisolated func start() async throws {
        guard let server = handle else { throw FFIError.invalidParameter("Server handle not initialized") }
        // Copy handle to local to avoid capturing actor state in closures
        let serverHandle = server
        let (code, err) = withRnErrorCode { errPtr in
            rn_transport_ca_server_start(serverHandle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to start CA Server") }
    }

    public nonisolated func bootstrapAddress() async throws -> String {
        guard let server = handle else { throw FFIError.invalidParameter("Server handle not initialized") }
        // Copy handle to local to avoid capturing actor state in closures
        let serverHandle = server
        var out: UnsafeMutablePointer<CChar>?
        let (code, err) = withRnErrorCode { errPtr in
            rn_transport_ca_server_get_bootstrap_addr(serverHandle, &out, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get bootstrap address") }
        return try copyCStringAndFree(out)
    }

    public nonisolated func authenticatedAddress() async throws -> String {
        guard let server = handle else { throw FFIError.invalidParameter("Server handle not initialized") }
        // Copy handle to local to avoid capturing actor state in closures
        let serverHandle = server
        var out: UnsafeMutablePointer<CChar>?
        let (code, err) = withRnErrorCode { errPtr in
            rn_transport_ca_server_get_authenticated_addr(serverHandle, &out, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get authenticated address") }
        return try copyCStringAndFree(out)
    }

    public nonisolated func configureAdminSkis(_ skisCbor: Data) async throws {
        guard let server = handle else { throw FFIError.invalidParameter("Server handle not initialized") }
        // Copy handle to local to avoid capturing actor state in closures
        let serverHandle = server
        let (code, err) = withRnErrorCode { errPtr in
            skisCbor.withUnsafeBytes { raw in
                rn_transport_ca_server_configure_admin_skis(
                    serverHandle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    skisCbor.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to configure admin SKIs") }
    }
    
    nonisolated deinit {
        if let server = _handle {
            rn_transport_ca_server_free(server)
            _handle = nil
        }
    }
}

// MARK: - Shared CA Node Wrapper

public final class SharedCANode {
    public nonisolated(unsafe) let handle: UnsafeMutableRawPointer
    nonisolated(unsafe) private let _handle: UnsafeMutableRawPointer

    public init(handle: UnsafeMutableRawPointer) {
        self.handle = handle
        self._handle = handle
    }

    public func addAdminSki(_ ski: String) async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let nodeHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            ski.withCString { cSki in
                rn_keys_ca_node_add_admin_ski(nodeHandle, cSki, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to add admin SKI") }
    }

    nonisolated deinit {
        rn_keys_ca_node_free_shared(_handle)
    }
}

// MARK: - CA Node Extensions

public extension CANode {
    func getRootCACertificate() async throws -> Data {
        let logger = RunarLogger(component: .custom)
        logger.debug("CANode.getRootCACertificate() - Getting Root CA certificate")
        // Copy handle to local to avoid capturing actor state in closures
        let caHandle = self.ffiHandle
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            logger.trace("CANode.getRootCACertificate() - About to call rn_keys_ca_node_get_root_ca_certificate")
            return rn_keys_ca_node_get_root_ca_certificate(caHandle, &outPtr, &outLen, errPtr)
        }
        logger.debug("CANode.getRootCACertificate() - FFI call completed, code: \(code), outLen: \(outLen)")
        if let error = err { 
            logger.error("CANode.getRootCACertificate() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("CANode.getRootCACertificate() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to get Root CA certificate") 
        }
        logger.debug("CANode.getRootCACertificate() - Root CA certificate retrieved successfully, length: \(outLen)")
        
        // Defensive check: fail fast if certificate is empty
        guard outLen > 0 else {
            throw FFIError.operationFailed("CA root certificate is empty; verify EA keys CBOR array and setup sequence - ensure configureEnrollmentAuthority was called before setupComplete")
        }
        
        return try copyBytesAndFree(outPtr, outLen)
    }

    func getIssuingCACertificate() async throws -> Data {
        let logger = RunarLogger(component: .custom)
        logger.debug("CANode.getIssuingCACertificate() - Getting Issuing CA certificate")
        // Copy handle to local to avoid capturing actor state in closures
        let caHandle = self.ffiHandle
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            logger.trace("CANode.getIssuingCACertificate() - About to call rn_keys_ca_node_get_issuing_ca_certificate")
            return rn_keys_ca_node_get_issuing_ca_certificate(caHandle, &outPtr, &outLen, errPtr)
        }
        logger.debug("CANode.getIssuingCACertificate() - FFI call completed, code: \(code), outLen: \(outLen)")
        if let error = err { 
            logger.error("CANode.getIssuingCACertificate() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("CANode.getIssuingCACertificate() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to get Issuing CA certificate") 
        }
        logger.debug("CANode.getIssuingCACertificate() - Issuing CA certificate retrieved successfully, length: \(outLen)")
        
        // Defensive check: fail fast if certificate is empty
        guard outLen > 0 else {
            throw FFIError.operationFailed("CA issuing certificate is empty; verify EA keys CBOR array and setup sequence - ensure configureEnrollmentAuthority was called before setupComplete")
        }
        
        return try copyBytesAndFree(outPtr, outLen)
    }

    func createSharedWrapped() async throws -> SharedCANode {
        // Since CANode.create() now creates shared handles directly, 
        // we can create a SharedCANode wrapper around the current handle
        return SharedCANode(handle: self.ffiHandle)
    }

    func handleCRL(networkId: String) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let caHandle = self.ffiHandle
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            networkId.withCString { cNet in
                rn_keys_ca_node_handle_crl(caHandle, cNet, &outPtr, &outLen, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to generate CRL-lite") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    func revokeToken(_ tokenId: String) async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let caHandle = self.ffiHandle
        let (code, err) = withRnErrorCode { errPtr in
            tokenId.withCString { cToken in
                rn_keys_ca_node_revoke_token(caHandle, cToken, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to revoke token") }
    }
    
    /// Configure enrollment authority
    /// - Parameter eaPublicKeys: Enrollment authority public keys data
    /// - Throws: FFIError if the operation fails
    func configureEnrollmentAuthority(eaPublicKeys: Data) async throws {
        let logger = RunarLogger(component: .custom)
        logger.debug("CANode.configureEnrollmentAuthority() - Configuring EA with keys length: \(eaPublicKeys.count)")
        
        // Copy handle to local to avoid capturing actor state in closures
        let caHandle = self.ffiHandle
        let (code, err) = withRnErrorCode { errPtr in
            logger.debug("CANode.configureEnrollmentAuthority() - Calling FFI function")
            return eaPublicKeys.withUnsafeBytes { raw in
                rn_keys_ca_node_configure_enrollment_authority(caHandle, raw.bindMemory(to: UInt8.self).baseAddress, eaPublicKeys.count, errPtr)
            }
        }
        logger.debug("CANode.configureEnrollmentAuthority() - FFI call completed, code: \(code)")
        if let error = err { 
            logger.error("CANode.configureEnrollmentAuthority() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("CANode.configureEnrollmentAuthority() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to configure enrollment authority") 
        }
        logger.info("CANode.configureEnrollmentAuthority() - EA configuration completed successfully")
    }
    
    /// Handle enrollment request (serverless)
    /// - Parameters:
    ///   - request: Enrollment request data
    ///   - remoteAddress: Remote client address
    /// - Returns: Enrollment response data
    /// - Throws: FFIError if the operation fails
    func handleEnroll(request: Data, remoteAddress: String) async throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        // Copy handle to local to avoid capturing actor state in closures
        let caHandle = self.ffiHandle
        let (code, err) = withRnErrorCode { errPtr in
            request.withUnsafeBytes { raw in
                remoteAddress.withCString { cAddr in
                    rn_keys_ca_node_handle_enroll(caHandle, raw.bindMemory(to: UInt8.self).baseAddress, request.count, cAddr, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to handle enrollment request") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    /// Handle renewal request (serverless)
    /// - Parameters:
    ///   - request: Renewal request data
    ///   - peerCertificate: Peer certificate data
    /// - Returns: Renewal response data
    /// - Throws: FFIError if the operation fails
    func handleRenew(request: Data, peerCertificate: Data) async throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        // Copy handle to local to avoid capturing actor state in closures
        let caHandle = self.ffiHandle
        let (code, err) = withRnErrorCode { errPtr in
            request.withUnsafeBytes { reqRaw in
                peerCertificate.withUnsafeBytes { certRaw in
                    rn_keys_ca_node_handle_renew(caHandle, reqRaw.bindMemory(to: UInt8.self).baseAddress, request.count, certRaw.bindMemory(to: UInt8.self).baseAddress, peerCertificate.count, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to handle renewal request") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    /// Handle revocation request (serverless)
    /// - Parameters:
    ///   - request: Revocation request data
    ///   - adminSki: Admin SKI (Subject Key Identifier)
    /// - Returns: Revocation response data
    /// - Throws: FFIError if the operation fails
    func handleRevoke(request: Data, adminSki: String) async throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        // Copy handle to local to avoid capturing actor state in closures
        let caHandle = self.ffiHandle
        let (code, err) = withRnErrorCode { errPtr in
            request.withUnsafeBytes { raw in
                adminSki.withCString { cSki in
                    rn_keys_ca_node_handle_revoke(caHandle, raw.bindMemory(to: UInt8.self).baseAddress, request.count, cSki, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to handle revocation request") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    /// Handle chain request (serverless)
    /// - Parameter networkId: Network ID
    /// - Returns: Chain response data
    /// - Throws: FFIError if the operation fails
    func handleChain(networkId: String) async throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        // Copy handle to local to avoid capturing actor state in closures
        let caHandle = self.ffiHandle
        let (code, err) = withRnErrorCode { errPtr in
            networkId.withCString { cNet in
                rn_keys_ca_node_handle_chain(caHandle, cNet, &outPtr, &outLen, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to handle chain request") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    /// Handle status request (serverless)
    /// - Parameter networkId: Network ID
    /// - Returns: Status response data
    /// - Throws: FFIError if the operation fails
    func handleStatus(networkId: String) async throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        // Copy handle to local to avoid capturing actor state in closures
        let caHandle = self.ffiHandle
        let (code, err) = withRnErrorCode { errPtr in
            networkId.withCString { cNet in
                rn_keys_ca_node_handle_status(caHandle, cNet, &outPtr, &outLen, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to handle status request") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    /// Generate CRL-lite (explicit API)
    /// - Returns: CRL-lite data
    /// - Throws: FFIError if the operation fails
    func generateCrlLite() async throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        // Copy handle to local to avoid capturing actor state in closures
        let caHandle = self.ffiHandle
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_ca_node_generate_crl_lite(caHandle, &outPtr, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to generate CRL-lite") }
        return try copyBytesAndFree(outPtr, outLen)
    }
}

// MARK: - Keys Wrapper

/// Handle for key management operations
/// 
/// This class provides a Swift interface to the Rust key management functionality.
/// It supports both node and mobile key management modes, including:
/// - Key generation and management
/// - Certificate operations
/// - Encryption and decryption
/// - Persistence and keystore operations
/// 
/// - Important: This class is not thread-safe. All operations should be performed
///   on the same queue/actor to ensure thread safety.
/// 

// MARK: - Unified Key Manager Classes

/// Node key manager implementation
///
/// This actor provides node-specific key management operations including certificate handling,
/// profile key management, and network key operations. It implements both CommonKeyManager
/// and NodeOnly protocols to provide a complete node key management interface.
public actor NodeKeyManager: NodeOnly, CommonKeyManager {
    /// The underlying Rust FFI handle
    private let _handle: SendableHandle
    
    /// Access to the FFI handle
    var handle: UnsafeMutableRawPointer { _handle.handle }


    /// Initialize a new node key manager
    /// 
    /// Creates a new key manager and initializes it specifically for node operations.
    /// This includes node key generation, certificate management, and network operations.
    /// 
    /// - Throws: FFIError if initialization fails
    public init() async throws {
        var out: UnsafeMutableRawPointer?
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_new(&out, errPtr)
        }
        if let error = err { throw error }
        guard code == 0, let handle = out else { throw FFIError.operationFailed("Failed to create keys handle") }
        self._handle = SendableHandle(handle)

        // Initialize as node
        // Copy handle to local to avoid capturing actor state in closures
        let nodeHandle = self.handle
        let (initCode, initErr) = withRnErrorCode { errPtr in
            rn_keys_init_as_node(nodeHandle, errPtr)
        }
        if let error = initErr { throw error }
        guard initCode == 0 else { throw FFIError.operationFailed("Failed to initialize as node") }
    }

    deinit {
        rn_keys_free(_handle.handle)
    }

    // MARK: - EnvelopeCryptoCommon Implementation

    public func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profilePublicKeys: [Data]) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_encrypt_with_envelope(handle, data: data, networkPublicKey: networkPublicKey, profilePublicKeys: profilePublicKeys)
    }

    public func decryptEnvelope(envelopeData: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_decrypt_envelope(handle, envelopeData: envelopeData)
    }

    // MARK: - NodeOnly Implementation

    public func hasKeys() async throws -> Bool {
        // Copy handle to local to avoid capturing actor state in closures
        let nodeHandle = self.handle
        var hasKeys: Int32 = 0
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_node_has_keys(nodeHandle, &hasKeys, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to check if node has keys") }
        return hasKeys != 0
    }

    public func generateKeys() async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let nodeHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_node_generate_keys(nodeHandle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to generate node keys") }
    }

    public func generateCsrSetupToken() async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_generate_csr(handle)
    }
    
    public func generateCSR() async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_generate_csr(handle)
    }

    public func installCertificate(_ certMessage: Data) async throws {
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

    public func getQuicCertificateConfig() async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_get_quic_certificate_config(handle)
    }

    public func getNodeCertificate() async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_get_node_certificate(handle)
    }

    public func getNodePublicKey() async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_get_public_key(handle)
    }

    public func deriveUserProfileKey(label: String) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_derive_user_profile_key(handle, label: label)
    }

    public func decryptWithProfile(envelopeData: Data, profileId: String) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_decrypt_with_profile(handle, envelopeData: envelopeData, profileId: profileId)
    }

    public func installProfilePublicKey(_ publicKey: Data) async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let nodeHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            publicKey.withUnsafeBytes { raw in
                rn_keys_node_install_profile_public_key(nodeHandle, raw.bindMemory(to: UInt8.self).baseAddress, publicKey.count, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to install profile public key") }
    }

    public func getProfilePublicKey(label: String) async throws -> (publicKey: Data?, exists: Bool) {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_get_profile_public_key_by_label(handle, label: label)
    }

    public func getCertificateStatus() async throws -> Int32 {
        // Copy handle to local to avoid capturing actor state in closures
        let nodeHandle = self.handle
        var status: Int32 = 0
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_node_get_certificate_status(nodeHandle, &status, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get certificate status") }
        return status
    }

    public func getCertificateSerial() async throws -> String {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_get_certificate_serial(handle)
    }

    public func validatePeerCertificate(_ cert: Data) async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let nodeHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            cert.withUnsafeBytes { raw in
                rn_keys_node_validate_peer_certificate(nodeHandle, raw.bindMemory(to: UInt8.self).baseAddress, cert.count, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to validate peer certificate") }
    }

    public func installNetworkKey(_ networkKeyMessage: Data) async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let nodeHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            networkKeyMessage.withUnsafeBytes { raw in
                rn_keys_node_install_network_key(nodeHandle, raw.bindMemory(to: UInt8.self).baseAddress, networkKeyMessage.count, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to install network key") }
    }

    public func getNetworkAgreement(networkPublicKey: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_get_network_agreement(handle, networkPublicKey: networkPublicKey)
    }
    
    public func hasNetworkPrivateKey(networkPublicKey: Data) async throws -> Bool {
        // Copy handle to local to avoid capturing actor state in closures
        let nodeHandle = self.handle
        var hasKey: Int32 = 0
        let (_, err) = withRnErrorCode { errPtr in
            networkPublicKey.withUnsafeBytes { raw in
                rn_keys_node_has_network_private_key(nodeHandle, raw.bindMemory(to: UInt8.self).baseAddress, networkPublicKey.count, &hasKey, errPtr)
            }
        }
        if let error = err { throw error }
        return hasKey != 0
    }

    public func getNodeAgreementPublicKey() async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_get_agreement_public_key(handle)
    }

    /// Get agreement public key (alias for getNodeAgreementPublicKey)
    /// - Returns: The agreement public key
    /// - Throws: FFIError if the operation fails
    public func getAgreementPublicKey() async throws -> Data {
        return try await getNodeAgreementPublicKey()
    }

    public func setLocalNodeInfo(_ nodeInfoCbor: Data) async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let nodeHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            nodeInfoCbor.withUnsafeBytes { raw in
                rn_keys_set_local_node_info(nodeHandle, raw.bindMemory(to: UInt8.self).baseAddress, nodeInfoCbor.count, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to set local node info") }
    }

    /// Get compact ID for a public key
    /// - Parameter key: Public key data
    /// - Returns: Compact ID string
    /// - Throws: FFIError if the operation fails
    public func getCompactId(for key: Data) async throws -> String {
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

    // MARK: - CommonKeyManager Implementation

    /// Ensure symmetric key exists with given name
    /// - Parameter name: Symmetric key name
    /// - Returns: Symmetric key data
    /// - Throws: FFIError if the operation fails
    public func ensureSymmetricKey(name: String) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_ensure_symmetric_key(handle, name: name)
    }
    
    /// Encrypt local data with default symmetric key
    /// - Parameter data: Data to encrypt
    /// - Returns: Encrypted data
    /// - Throws: FFIError if encryption fails
    public func encryptLocalData(data: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_encrypt_local_data(handle, data: data)
    }

    /// Decrypt local data with default symmetric key
    /// - Parameter encryptedData: Encrypted data
    /// - Returns: Decrypted data
    /// - Throws: FFIError if decryption fails
    public func decryptLocalData(encryptedData: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_decrypt_local_data(handle, encryptedData: encryptedData)
    }
    
    /// Set persistence directory
    /// - Parameter path: Directory path for persistence
    /// - Throws: FFIError if the operation fails
    public func setPersistenceDirectory(_ path: String) async throws {
        let (code, err) = withRnErrorCode { errPtr in
            path.withCString { pathPtr in
                rn_keys_set_persistence_dir(handle, pathPtr, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to set persistence directory") }
    }
    
    /// Enable or disable auto-persistence
    /// - Parameter enabled: Whether to enable auto-persistence
    /// - Throws: FFIError if the operation fails
    public func enableAutoPersistence(_ enabled: Bool) async throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_enable_auto_persist(handle, enabled, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to enable auto-persistence") }
    }
    
    /// Wipe persistence data
    /// - Throws: FFIError if the operation fails
    public func wipePersistence() async throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_wipe_persistence(handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to wipe persistence") }
    }
    
    /// Get keystore capabilities
    /// - Returns: Keystore capabilities information
    /// - Throws: FFIError if the operation fails
    public func getKeystoreCapabilities() async throws -> KeystoreCapabilities {
        var caps = RnDeviceKeystoreCaps(version: 0, flags: 0)
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_get_keystore_caps(handle, &caps, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get keystore capabilities") }
        return KeystoreCapabilities(version: caps.version, flags: caps.flags)
    }
    
    /// Flush state to persistence
    /// - Throws: FFIError if the operation fails
    public func flushState() async throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_flush_state(handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to flush state") }
    }
    
    /// Register Apple device keystore
    /// - Parameter label: Keystore label
    /// - Throws: FFIError if the operation fails
    public func registerAppleDeviceKeystore(label: String) async throws {
        let (code, err) = withRnErrorCode { errPtr in
            label.withCString { labelPtr in
                rn_keys_register_apple_device_keystore(handle, labelPtr, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to register Apple device keystore") }
    }
    
    
    /// Encrypt data for network
    /// - Parameters:
    ///   - data: Data to encrypt
    ///   - networkPublicKey: Network public key
    /// - Returns: Encrypted data
    /// - Throws: FFIError if encryption fails
    public func encryptForNetwork(data: Data, networkPublicKey: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_encrypt_for_network(handle, data: data, networkPublicKey: networkPublicKey)
    }
    
    /// Decrypt network data
    /// - Parameter encryptedEnvelope: Encrypted envelope data
    /// - Returns: Decrypted data
    /// - Throws: FFIError if decryption fails
    public func decryptNetworkData(encryptedEnvelope: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_decrypt_network_data(handle, encryptedEnvelope: encryptedEnvelope)
    }

    // MARK: - NodeOnly Message Crypto Implementation

    /// Encrypt message for mobile device
    /// - Parameters:
    ///   - data: Data to encrypt
    ///   - mobilePublicKey: Mobile device public key
    /// - Returns: Encrypted message data
    /// - Throws: FFIError if encryption fails
    public func encryptMessageForMobile(data: Data, mobilePublicKey: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_encrypt_message_for_mobile(handle, data: data, mobilePublicKey: mobilePublicKey)
    }

    /// Decrypt message from mobile device
    /// - Parameter encryptedData: Encrypted message data
    /// - Returns: Decrypted data
    /// - Throws: FFIError if decryption fails
    public func decryptMessageFromMobile(encryptedData: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_decrypt_message_from_mobile(handle, encryptedData: encryptedData)
    }
    
    // MARK: - Helper Methods for External Objects
    
    /// Actor-safe factory: create a CAClient instance
    public func createCAClient(config: CaClientConfigAll, configCbor: Data? = nil) async throws -> CAClient {
        let cbor: Data
        if let provided = configCbor {
            cbor = provided
        } else {
            cbor = try await ffi_encode_ca_client_config(config)
        }
        let nodeHandle = self.handle
        let clientHandle = try ffi_create_ca_client(nodeHandle, configCbor: cbor)
        return CAClient(handle: clientHandle)
    }
    
    /// Create a discovery handle with this node's handle
    public func createDiscoveryHandle(optionsCbor: Data) async throws -> DiscoveryHandle {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        let discoveryHandle = try ffi_create_discovery(handle, optionsCbor: optionsCbor)
        return DiscoveryHandle(handle: discoveryHandle)
    }
    
    /// Create a transport handle with this node's handle
    public func createTransportHandle(optionsCbor: Data) async throws -> TransportHandle {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        let transportHandle = try ffi_create_transport(handle, optionsCbor: optionsCbor)
        return TransportHandle(handle: transportHandle)
    }
}

/// Mobile key manager implementation
///
/// This actor provides mobile-specific key management operations including user key initialization,
/// network key exchange, and certificate processing. It implements both CommonKeyManager
/// and MobileOnly protocols to provide a complete mobile key management interface.
public actor MobileKeyManager: MobileOnly, CommonKeyManager {
    /// The underlying Rust FFI handle
    private let _handle: SendableHandle
    
    /// Access to the FFI handle
    var handle: UnsafeMutableRawPointer { _handle.handle }
    

    /// Initialize a new mobile key manager
    ///
    /// Creates a new key manager and initializes it specifically for mobile operations.
    /// This includes user key management, network key exchange, and certificate processing.
    ///
    /// - Throws: FFIError if initialization fails
    public init() async throws {
        var out: UnsafeMutableRawPointer?
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_new(&out, errPtr)
        }
        if let error = err { throw error }
        guard code == 0, let handle = out else { throw FFIError.operationFailed("Failed to create keys handle") }
        self._handle = SendableHandle(handle)

        // Initialize as mobile
        // Copy handle to local to avoid capturing actor state in closures
        let mobileHandle = self.handle
        let (initCode, initErr) = withRnErrorCode { errPtr in
            rn_keys_init_as_mobile(mobileHandle, errPtr)
        }
        if let error = initErr { throw error }
        guard initCode == 0 else { throw FFIError.operationFailed("Failed to initialize as mobile") }
    }

    deinit {
        rn_keys_free(_handle.handle)
    }

    // MARK: - EnvelopeCryptoCommon Implementation

    public func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profilePublicKeys: [Data]) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_mobile_encrypt_with_envelope(handle, data: data, networkPublicKey: networkPublicKey, profilePublicKeys: profilePublicKeys)
    }
    
    public func decryptEnvelope(envelopeData: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_decrypt_envelope(handle, envelopeData: envelopeData)
    }
    
    // MARK: - MobileOnly Implementation

    public func initializeUserRootKey() async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let mobileHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_mobile_initialize_user_root_key(mobileHandle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to initialize user root key") }
    }

    public func getUserPublicKey() async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_mobile_get_user_public_key(handle)
    }

    public func deriveUserProfileKey(label: String) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_mobile_derive_user_profile_key(handle, label: label)
    }
    
    public func installNetworkPublicKey(_ networkPublicKey: Data) async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let mobileHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            networkPublicKey.withUnsafeBytes { raw in
                rn_keys_mobile_install_network_public_key(mobileHandle, raw.bindMemory(to: UInt8.self).baseAddress, networkPublicKey.count, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to install network public key") }
    }
    
    public func generateNetworkDataKey() async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_mobile_generate_network_data_key(handle)
    }
    
    public func hasNetworkPrivateKey(networkPublicKey: Data) async throws -> Bool {
        // Copy handle to local to avoid capturing actor state in closures
        let mobileHandle = self.handle
        var hasKey: Int32 = 0
        let (_, err) = withRnErrorCode { errPtr in
            networkPublicKey.withUnsafeBytes { raw in
                rn_keys_mobile_has_network_private_key(mobileHandle, raw.bindMemory(to: UInt8.self).baseAddress, networkPublicKey.count, &hasKey, errPtr)
            }
        }
        if let error = err { throw error }
        return hasKey != 0
    }
    
    public func createNetworkKeyMessage(networkPublicKey: Data, nodeAgreementPublicKey: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_mobile_create_network_key_message(handle, data: networkPublicKey, nodeAgreementPublicKey: nodeAgreementPublicKey)
    }
    
    public func processSetupToken(_ setupToken: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_mobile_process_setup_token(handle, setupToken: setupToken)
    }
    
    public func fromEnrollResponse(_ response: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_mobile_from_enroll_response(handle, response: response)
    }
    
    public func fromRenewResponse(_ response: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_mobile_from_renew_response(handle, response: response)
    }
    
    /// Get compact ID for a public key
    /// - Parameter key: Public key data
    /// - Returns: Compact ID string
    /// - Throws: FFIError if the operation fails
    public func getCompactId(for key: Data) async throws -> String {
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

    // MARK: - CommonKeyManager Implementation

    /// Ensure symmetric key exists with given name
    /// - Parameter name: Symmetric key name
    /// - Returns: Symmetric key data
    /// - Throws: FFIError if the operation fails
    public func ensureSymmetricKey(name: String) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_ensure_symmetric_key(handle, name: name)
    }
    
    /// Encrypt local data with default symmetric key
    /// - Parameter data: Data to encrypt
    /// - Returns: Encrypted data
    /// - Throws: FFIError if encryption fails
    public func encryptLocalData(data: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_encrypt_local_data(handle, data: data)
    }
    
    /// Decrypt local data with default symmetric key
    /// - Parameter encryptedData: Encrypted data
    /// - Returns: Decrypted data
    /// - Throws: FFIError if decryption fails
    public func decryptLocalData(encryptedData: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_decrypt_local_data(handle, encryptedData: encryptedData)
    }
    
    /// Set persistence directory
    /// - Parameter path: Directory path for persistence
    /// - Throws: FFIError if the operation fails
    public func setPersistenceDirectory(_ path: String) async throws {
        let (code, err) = withRnErrorCode { errPtr in
            path.withCString { pathPtr in
                rn_keys_set_persistence_dir(handle, pathPtr, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to set persistence directory") }
    }
    
    /// Enable or disable auto-persistence
    /// - Parameter enabled: Whether to enable auto-persistence
    /// - Throws: FFIError if the operation fails
    public func enableAutoPersistence(_ enabled: Bool) async throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_enable_auto_persist(handle, enabled, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to enable auto-persistence") }
    }
    
    /// Wipe persistence data
    /// - Throws: FFIError if the operation fails
    public func wipePersistence() async throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_wipe_persistence(handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to wipe persistence") }
    }
    
    /// Get keystore capabilities
    /// - Returns: Keystore capabilities information
    /// - Throws: FFIError if the operation fails
    public func getKeystoreCapabilities() async throws -> KeystoreCapabilities {
        var caps = RnDeviceKeystoreCaps(version: 0, flags: 0)
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_get_keystore_caps(handle, &caps, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get keystore capabilities") }
        return KeystoreCapabilities(version: caps.version, flags: caps.flags)
    }
    
    /// Flush state to persistence
    /// - Throws: FFIError if the operation fails
    public func flushState() async throws {
        let (code, err) = withRnErrorCode { errPtr in
            rn_keys_flush_state(handle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to flush state") }
    }
    
    /// Register Apple device keystore
    /// - Parameter label: Keystore label
    /// - Throws: FFIError if the operation fails
    public func registerAppleDeviceKeystore(label: String) async throws {
        let (code, err) = withRnErrorCode { errPtr in
            label.withCString { labelPtr in
                rn_keys_register_apple_device_keystore(handle, labelPtr, errPtr)
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to register Apple device keystore") }
    }


    /// Encrypt data for network
    /// - Parameters:
    ///   - data: Data to encrypt
    ///   - networkPublicKey: Network public key
    /// - Returns: Encrypted data
    /// - Throws: FFIError if encryption fails
    public func encryptForNetwork(data: Data, networkPublicKey: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_encrypt_for_network(handle, data: data, networkPublicKey: networkPublicKey)
    }
    
    /// Decrypt network data
    /// - Parameter encryptedEnvelope: Encrypted envelope data
    /// - Returns: Decrypted data
    /// - Throws: FFIError if decryption fails
    public func decryptNetworkData(encryptedEnvelope: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_decrypt_network_data(handle, encryptedEnvelope: encryptedEnvelope)
    }

    // MARK: - MobileOnly Message Crypto Implementation

    /// Encrypt message for node device
    /// - Parameters:
    ///   - data: Data to encrypt
    ///   - nodeAgreementPublicKey: Node agreement public key
    /// - Returns: Encrypted message data
    /// - Throws: FFIError if encryption fails
    public func encryptMessageForNode(data: Data, nodeAgreementPublicKey: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_encrypt_message_for_node(handle, data: data, nodeAgreementPublicKey: nodeAgreementPublicKey)
    }
    
    /// Decrypt message from node device
    /// - Parameter encryptedData: Encrypted message data
    /// - Returns: Decrypted data
    /// - Throws: FFIError if decryption fails
    public func decryptMessageFromNode(encryptedData: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle

        // Call nonisolated helper - no suspension during FFI
        return try ffi_mobile_decrypt_message_from_node(handle, encryptedData: encryptedData)
    }
    
    /// Generate CSR for certificate enrollment
    /// - Returns: CSR data
    /// - Throws: FFIError if generation fails
    public func generateCSR() async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        // Call nonisolated helper - no suspension during FFI
        return try ffi_node_generate_csr(handle)
    }
    
    /// Install certificate from CA response
    /// - Parameter certMessage: Certificate message data
    /// - Throws: FFIError if installation fails
    public func installCertificate(_ certMessage: Data) async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let mobileHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            certMessage.withUnsafeBytes { raw in
                rn_keys_node_install_certificate(
                    mobileHandle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    certMessage.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to install certificate") }
    }
    
    /// Decrypt data with profile key
    /// - Parameters:
    ///   - data: Encrypted data
    ///   - profileId: Profile ID
    /// - Returns: Decrypted data
    /// - Throws: FFIError if decryption fails
    public func decryptWithProfile(_ data: Data, _ profileId: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let mobileHandle = self.handle
        return try ffi_node_decrypt_with_profile(mobileHandle, envelopeData: data, profileId: String(data: profileId, encoding: .utf8) ?? "")
    }
}

// MARK: - CA Client Wrapper

public final class CAClient: Sendable {
    private let _handleWrapper: SendableHandle
    var handle: UnsafeMutableRawPointer { _handleWrapper.handle }
    @MainActor private static var _liveCount: Int = 0
    @MainActor private static func _inc() { _liveCount += 1 }
    @MainActor private static func _dec() { _liveCount -= 1 }

    // Use NodeKeyManager factory to create instances; keep this internal
    internal init(handle: UnsafeMutableRawPointer) {
        self._handleWrapper = SendableHandle(handle)
        let logger = RunarLogger(component: .custom)
        let threadId = pthread_mach_thread_np(pthread_self())
        Task { @MainActor in CAClient._inc() }
        logger.trace("CAClient.init: thread=\(threadId) clientHandle=\(handle)")
    }
    
    public func enroll(bootstrapAddress: String, request: Data) async throws -> Data {
        let logger = RunarLogger(component: .custom)
        logger.info("CAClient.enroll() - Starting enrollment")
        logger.debug("CAClient.enroll() - Bootstrap address: \(bootstrapAddress)")
        logger.debug("CAClient.enroll() - Request data length: \(request.count)")
        
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        logger.debug("CAClient.enroll() - Handle copied to local")
        
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        logger.trace("CAClient.enroll() - About to call FFI function")
        let (code, err) = withRnErrorCode { errPtr in
            bootstrapAddress.withCString { cAddr in
                request.withUnsafeBytes { raw in
                    logger.trace("CAClient.enroll() - Inside FFI call")
                    return rn_transport_ca_client_enroll(handle, cAddr, raw.bindMemory(to: UInt8.self).baseAddress, request.count, &outPtr, &outLen, errPtr)
                }
            }
        }
        logger.debug("CAClient.enroll() - FFI call completed, code: \(code)")
        if let error = err { 
            logger.error("CAClient.enroll() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("CAClient.enroll() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to enroll") 
        }
        logger.debug("CAClient.enroll() - About to copy and free result")
        let result = try copyBytesAndFree(outPtr, outLen)
        logger.debug("CAClient.enroll() - Enrollment completed successfully, result length: \(result.count)")
        return result
    }

    public func renew(authenticatedAddress: String, request: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            authenticatedAddress.withCString { cAddr in
                request.withUnsafeBytes { raw in
                    rn_transport_ca_client_renew(handle, cAddr, raw.bindMemory(to: UInt8.self).baseAddress, request.count, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to renew certificate") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func revoke(authenticatedAddress: String, request: Data) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            authenticatedAddress.withCString { cAddr in
                request.withUnsafeBytes { raw in
                    rn_transport_ca_client_revoke(handle, cAddr, raw.bindMemory(to: UInt8.self).baseAddress, request.count, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to revoke certificate") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func getStatus(authenticatedAddress: String, networkId: String) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            authenticatedAddress.withCString { cAddr in
                networkId.withCString { cNet in
                    rn_transport_ca_client_get_status(handle, cAddr, cNet, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get status") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    public func getChain(bootstrapAddress: String, networkId: String) async throws -> Data {
        // Copy handle to local to avoid capturing actor state in closures
        let handle = self.handle
        
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            bootstrapAddress.withCString { cAddr in
                networkId.withCString { cNet in
                    rn_transport_ca_client_get_chain(handle, cAddr, cNet, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get chain") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    /// Get CRL (Certificate Revocation List)
    /// - Parameters:
    ///   - authenticatedAddress: Authenticated server address
    ///   - networkId: Network ID
    /// - Returns: CRL data
    /// - Throws: FFIError if the operation fails
    public func getCrl(authenticatedAddress: String, networkId: String) async throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        // Copy handle to local to avoid capturing actor state in closures
        let clientHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            authenticatedAddress.withCString { cAddr in
                networkId.withCString { cNet in
                    rn_transport_ca_client_get_crl(clientHandle, cAddr, cNet, &outPtr, &outLen, errPtr)
                }
            }
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to get CRL") }
        return try copyBytesAndFree(outPtr, outLen)
    }

    deinit {
        let logger = RunarLogger(component: .custom)
        let threadId = pthread_mach_thread_np(pthread_self())
        logger.trace("CAClient.deinit: thread=\(threadId) clientHandle=\(_handleWrapper.handle)")
        rn_transport_ca_client_free(_handleWrapper.handle)
        Task { @MainActor in CAClient._dec() }
    }
}

// MARK: - Certificate Utilities

public enum CertificateUtils {
    public static func extractSki(from certificateDer: Data) async throws -> String {
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

    public static func getSerialHex(from certificateDer: Data) async throws -> String {
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

// MARK: - Hex Utilities

// keep using the existing Data.init?(hexString:) declared earlier (at ~1362)

// MARK: - Enrollment Token Utilities

public enum EnrollmentTokenUtils {
    /// Generate enrollment token (low-level utility)
    /// - Parameters:
    ///   - eaKey: Enrollment authority key data
    ///   - tokenId: Token ID
    ///   - networkId: Network ID
    ///   - subject: Subject name
    ///   - notBefore: Valid from timestamp
    ///   - expiresAt: Expiration timestamp
    ///   - nonce: Nonce data
    ///   - permissions: Permissions data (CBOR encoded)
    /// - Returns: Generated token data
    /// - Throws: FFIError if the operation fails
    public static func generateToken(eaKey: Data, tokenId: String, networkId: String, subject: String, notBefore: UInt64, expiresAt: UInt64, nonce: Data, permissions: Data) async throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            eaKey.withUnsafeBytes { keyRaw in
                nonce.withUnsafeBytes { nonceRaw in
                    permissions.withUnsafeBytes { permRaw in
                        tokenId.withCString { cTokenId in
                            networkId.withCString { cNetworkId in
                                subject.withCString { cSubject in
                                    rn_keys_enrollment_token_generate(
                                        keyRaw.bindMemory(to: UInt8.self).baseAddress,
                                        eaKey.count,
                                        cTokenId,
                                        cNetworkId,
                                        cSubject,
                                        notBefore,
                                        expiresAt,
                                        nonceRaw.bindMemory(to: UInt8.self).baseAddress,
                                        nonce.count,
                                        permRaw.bindMemory(to: UInt8.self).baseAddress,
                                        permissions.count,
                                        &outPtr,
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
        guard code == 0 else { throw FFIError.operationFailed("Failed to generate enrollment token") }
        return try copyBytesAndFree(outPtr, outLen)
    }
    
    /// Validate enrollment token (low-level utility)
    /// - Parameters:
    ///   - token: Token data to validate
    ///   - eaPublicKey: Enrollment authority public key
    /// - Returns: True if token is valid, false otherwise
    /// - Throws: FFIError if the operation fails
    public static func validateToken(_ token: Data, eaPublicKey: Data) async throws -> Bool {
        var isValid: Int32 = 0
        let (code, err) = withRnErrorCode { errPtr in
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
        guard code == 0 else { throw FFIError.operationFailed("Failed to validate enrollment token") }
        return isValid != 0
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
public enum CBORHelper {
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
            openStreamTimeoutMs: 10000,
            maxMessageSize: 1024,
            responseCacheTtlMs: 30000,
            maxRequestRetries: 3
        )
    }
    
    /// Encode NodeInfo to CBOR data
    @MainActor
    public static func encodeNodeInfo(_ nodeInfo: NodeInfo) async throws -> Data {
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
    @MainActor public static func encodeTransportOptions(_ options: QuicTransportOptionsCbor) async throws -> Data {
        // Create CBOR map manually to match Rust structure
        var map: [CBOR: CBOR] = [:]
        
        // Always include bindAddr - it's required
        let bindAddr = options.bindAddr ?? "127.0.0.1:0"
            map[.utf8String("bind_addr")] = .utf8String(bindAddr)
        
        // Always include required fields with defaults
        let handshakeTimeoutMs = options.handshakeTimeoutMs ?? 5000
            map[.utf8String("handshake_timeout_ms")] = .unsignedInt(handshakeTimeoutMs)
        
        let openStreamTimeoutMs = options.openStreamTimeoutMs ?? 10000
            map[.utf8String("open_stream_timeout_ms")] = .unsignedInt(openStreamTimeoutMs)
        
        let maxMessageSize = options.maxMessageSize ?? 1024
            map[.utf8String("max_message_size")] = .unsignedInt(maxMessageSize)
        
        let responseCacheTtlMs = options.responseCacheTtlMs ?? 30000
            map[.utf8String("response_cache_ttl_ms")] = .unsignedInt(responseCacheTtlMs)
        
        let maxRequestRetries = options.maxRequestRetries ?? 3
            map[.utf8String("max_request_retries")] = .unsignedInt(UInt64(maxRequestRetries))
        
        return Data(CBOR.map(map).encode())
    }
    
    /// Encode CaClientConfigAll to CBOR data
    @MainActor
    public static func encodeCaClientConfig(_ config: CaClientConfigAll) async throws -> Data {
        // Create CBOR map manually to match Rust structure
        var map: [CBOR: CBOR] = [:]
        
        map[.utf8String("bootstrap_server")] = .utf8String(config.bootstrap_server)
        map[.utf8String("authenticated_server")] = .utf8String(config.authenticated_server)
        map[.utf8String("network_id")] = .utf8String(config.network_id)
        map[.utf8String("request_timeout_seconds")] = .unsignedInt(UInt64(config.request_timeout_seconds))
        map[.utf8String("max_retries")] = .unsignedInt(UInt64(config.max_retries))
        map[.utf8String("root_ca_der")] = .array([UInt8](config.root_ca_der).map { .unsignedInt(UInt64($0)) })
        map[.utf8String("issuing_ca_der")] = .array([UInt8](config.issuing_ca_der).map { .unsignedInt(UInt64($0)) })
        
        return Data(CBOR.map(map).encode())
    }
    
    /// Encode PeerInfo to CBOR data
    @MainActor
    public static func encodePeerInfo(_ peerInfo: PeerInfo) async throws -> Data {
        // Create CBOR map manually to match Rust structure
        var map: [CBOR: CBOR] = [:]
        map[.utf8String("public_key")] = .array([UInt8](peerInfo.publicKey).map { .unsignedInt(UInt64($0)) })
        map[.utf8String("addresses")] = .array(peerInfo.addresses.map { .utf8String($0) })
        
        return Data(CBOR.map(map).encode())
    }
    
    /// Encode TransportRequestParams to CBOR data using manual CBOR map creation
    @MainActor
    public static func encodeTransportRequestParams(_ params: TransportRequestParams) async throws -> Data {
        // Debug logging removed per production standards
        
        // Use automatic Codable encoding since struct now matches Rust types exactly
        let encoder = CodableCBOREncoder()
        let cborData = try encoder.encode(params)
        
        // Debug logging removed per production standards
        
        return cborData
    }
    
    /// Encode TransportCompleteRequestParams to CBOR data using automatic Codable encoding
    @MainActor
    public static func encodeTransportCompleteRequestParams(_ params: TransportCompleteRequestParams) async throws -> Data {
        // Use automatic Codable encoding since struct now matches Rust types exactly
        let encoder = CodableCBOREncoder()
        return try encoder.encode(params)
    }
}

// MARK: - Transport Request/Response Structures

/// Swift representation of TransportRequestParams from Rust FFI
/// Matches Rust struct exactly: Vec<u8> becomes [UInt8]
public struct TransportRequestParams: Codable {
    public let path: String
    public let correlationId: String
    public let payload: [UInt8]  // Vec<u8> in Rust
    public let destPeerId: String
    public let networkPublicKey: [UInt8]?  // Option<Vec<u8>> in Rust
    public let profilePublicKeys: [[UInt8]]  // Vec<Vec<u8>> in Rust
    
    public init(path: String, correlationId: String, payload: [UInt8], destPeerId: String, networkPublicKey: [UInt8]? = nil, profilePublicKeys: [[UInt8]] = []) {
        self.path = path
        self.correlationId = correlationId
        self.payload = payload
        self.destPeerId = destPeerId
        self.networkPublicKey = networkPublicKey
        self.profilePublicKeys = profilePublicKeys
    }
    
    // Convenience initializer that accepts Data and converts to [UInt8]
    public init(path: String, correlationId: String, payload: Data, destPeerId: String, networkPublicKey: Data? = nil, profilePublicKeys: [Data] = []) {
        self.path = path
        self.correlationId = correlationId
        self.payload = [UInt8](payload)
        self.destPeerId = destPeerId
        self.networkPublicKey = networkPublicKey.map { [UInt8]($0) }
        self.profilePublicKeys = profilePublicKeys.map { [UInt8]($0) }
    }
    
    enum CodingKeys: String, CodingKey {
        case path
        case correlationId = "correlation_id"
        case payload
        case destPeerId = "dest_peer_id"
        case networkPublicKey = "network_public_key"
        case profilePublicKeys = "profile_public_keys"
    }
}

/// Swift representation of TransportCompleteRequestParams from Rust FFI
/// Matches Rust struct exactly: Vec<u8> becomes [UInt8]
public struct TransportCompleteRequestParams: Codable {
    public let requestId: String
    public let responsePayload: [UInt8]  // Vec<u8> in Rust
    public let profilePublicKeys: [[UInt8]]  // Vec<Vec<u8>> in Rust
    
    public init(requestId: String, responsePayload: [UInt8], profilePublicKeys: [[UInt8]] = []) {
        self.requestId = requestId
        self.responsePayload = responsePayload
        self.profilePublicKeys = profilePublicKeys
    }
    
    // Convenience initializer that accepts Data and converts to [UInt8]
    public init(requestId: String, responsePayload: Data, profilePublicKeys: [Data] = []) {
        self.requestId = requestId
        self.responsePayload = [UInt8](responsePayload)
        self.profilePublicKeys = profilePublicKeys.map { [UInt8]($0) }
    }
    
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case responsePayload = "response_payload"
        case profilePublicKeys = "profile_public_keys"
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
    
    public func encode(to encoder: Encoder) async throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Array(publicKey), forKey: .publicKey)
        try container.encode(addresses, forKey: .addresses)
    }
    
    public init(from decoder: Decoder) async throws {
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
                debounceWindowMs: UInt32 = 200)
    {
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
public class DiscoveryHandle: @unchecked Sendable {
    private let handle: UnsafeMutableRawPointer
    
    public init(handle: UnsafeMutableRawPointer) {
        self.handle = handle
    }
    
    deinit {
        rn_discovery_free(handle)
    }
    
    /// Create a new discovery instance with multicast
    public static func create(keys: NodeKeyManager, optionsCbor: Data) async throws -> DiscoveryHandle {
        return try await keys.createDiscoveryHandle(optionsCbor: optionsCbor)
    }
    
    /// Initialize discovery with options
    public func initialize(optionsCbor: Data) async throws {
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
    public func bindEventsToTransport(transport: TransportHandle) async throws {
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
    public func startAnnouncing() async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let discoveryHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            rn_discovery_start_announcing(discoveryHandle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to start announcing") }
    }
    
    /// Stop announcing this node
    public func stopAnnouncing() async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let discoveryHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            rn_discovery_stop_announcing(discoveryHandle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to stop announcing") }
    }
    
    /// Shutdown discovery
    public func shutdown() async throws {
        // Copy handle to local to avoid capturing actor state in closures
        let discoveryHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            rn_discovery_shutdown(discoveryHandle, errPtr)
        }
        if let error = err { throw error }
        guard code == 0 else { throw FFIError.operationFailed("Failed to shutdown discovery") }
    }
    
    /// Update local peer info
    public func updateLocalPeerInfo(peerInfoCbor: Data) async throws {
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
public class TransportHandle: @unchecked Sendable {
    private let handle: UnsafeMutableRawPointer
    
    public init(handle: UnsafeMutableRawPointer) {
        self.handle = handle
    }
    
    /// Get the raw handle for internal use
    var rawHandle: UnsafeMutableRawPointer {
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
    public static func create(keys: NodeKeyManager, optionsCbor: Data) async throws -> TransportHandle {
        return try await keys.createTransportHandle(optionsCbor: optionsCbor)
    }
    
    /// Start the transport
    /// - Throws: FFIError if start fails
    public func start() async throws {
        let logger = RunarLogger(component: .custom)
        logger.info("TransportHandle.start() - Starting transport")
        // Copy handle to local to avoid capturing actor state in closures
        let transportHandle = self.handle
        logger.debug("TransportHandle.start() - Handle copied to local")
        let (code, err) = withRnErrorCode { errPtr in
            logger.trace("TransportHandle.start() - About to call rn_transport_start")
            return rn_transport_start(transportHandle, errPtr)
        }
        logger.debug("TransportHandle.start() - FFI call completed, code: \(code)")
        if let error = err { 
            logger.error("TransportHandle.start() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("TransportHandle.start() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to start transport") 
        }
        logger.info("TransportHandle.start() - Transport started successfully")
    }
    
    /// Poll for events
    /// - Returns: Event data if available, nil if no events
    /// - Throws: FFIError if polling fails
    public func pollEvent() async throws -> Data? {
        let logger = RunarLogger(component: .custom)
        logger.debug("TransportHandle.pollEvent() - Polling for events")
        // Copy handle to local to avoid capturing actor state in closures
        let transportHandle = self.handle
        var outEvent: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            logger.trace("TransportHandle.pollEvent() - About to call rn_transport_poll_event")
            return rn_transport_poll_event(transportHandle, &outEvent, &outLen, errPtr)
        }
        logger.debug("TransportHandle.pollEvent() - FFI call completed, code: \(code), outLen: \(outLen)")
        if let error = err { 
            logger.error("TransportHandle.pollEvent() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("TransportHandle.pollEvent() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to poll event") 
        }
        
        if outLen == 0 {
            logger.debug("TransportHandle.pollEvent() - No events available")
            return nil
        }
        
        logger.debug("TransportHandle.pollEvent() - Event available, copying data")
        return try copyBytesAndFree(outEvent, outLen)
    }
    
    /// Connect to a peer
    /// - Parameter peerInfoCbor: Peer information in CBOR format
    /// - Throws: FFIError if connection fails
    public func connectPeer(peerInfoCbor: Data) async throws {
        let logger = RunarLogger(component: .custom)
        logger.debug("TransportHandle.connectPeer() - Connecting to peer")
        logger.debug("TransportHandle.connectPeer() - PeerInfo CBOR length: \(peerInfoCbor.count)")
        // Copy handle to local to avoid capturing actor state in closures
        let transportHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            peerInfoCbor.withUnsafeBytes { raw in
                logger.trace("TransportHandle.connectPeer() - About to call rn_transport_connect_peer")
                return rn_transport_connect_peer(transportHandle, raw.bindMemory(to: UInt8.self).baseAddress, peerInfoCbor.count, errPtr)
            }
        }
        logger.debug("TransportHandle.connectPeer() - FFI call completed, code: \(code)")
        if let error = err { 
            logger.error("TransportHandle.connectPeer() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("TransportHandle.connectPeer() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to connect to peer") 
        }
        logger.info("TransportHandle.connectPeer() - Peer connected successfully")
    }
    
    /// Disconnect from a peer
    /// - Parameter peerNodeId: Node ID of the peer to disconnect
    /// - Throws: FFIError if disconnection fails
    public func disconnectPeer(peerNodeId: String) async throws {
        let logger = RunarLogger(component: .custom)
        logger.debug("TransportHandle.disconnectPeer() - Disconnecting from peer: \(peerNodeId)")
        // Copy handle to local to avoid capturing actor state in closures
        let transportHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            peerNodeId.withCString { cString in
                logger.trace("TransportHandle.disconnectPeer() - About to call rn_transport_disconnect_peer")
                return rn_transport_disconnect_peer(transportHandle, cString, errPtr)
            }
        }
        logger.debug("TransportHandle.disconnectPeer() - FFI call completed, code: \(code)")
        if let error = err { 
            logger.error("TransportHandle.disconnectPeer() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("TransportHandle.disconnectPeer() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to disconnect from peer") 
        }
        logger.info("TransportHandle.disconnectPeer() - Peer disconnected successfully")
    }
    
    /// Check if connected to a peer
    /// - Parameter peerNodeId: Node ID of the peer to check
    /// - Returns: True if connected, false otherwise
    /// - Throws: FFIError if check fails
    public func isConnected(peerNodeId: String) async throws -> Bool {
        let logger = RunarLogger(component: .custom)
        logger.debug("TransportHandle.isConnected() - Checking connection to peer: \(peerNodeId)")
        // Copy handle to local to avoid capturing actor state in closures
        let transportHandle = self.handle
        var outConnected = false
        let (code, err) = withRnErrorCode { errPtr in
            peerNodeId.withCString { cString in
                logger.trace("TransportHandle.isConnected() - About to call rn_transport_is_connected")
                return rn_transport_is_connected(transportHandle, cString, &outConnected, errPtr)
            }
        }
        logger.debug("TransportHandle.isConnected() - FFI call completed, code: \(code), connected: \(outConnected)")
        if let error = err { 
            logger.error("TransportHandle.isConnected() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("TransportHandle.isConnected() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to check connection status") 
        }
        logger.debug("TransportHandle.isConnected() - Connection check completed: \(outConnected)")
        return outConnected
    }
    
    /// Update local node information
    /// - Parameter nodeInfoCbor: Node information in CBOR format
    /// - Throws: FFIError if update fails
    public func updateLocalNodeInfo(nodeInfoCbor: Data) async throws {
        let logger = RunarLogger(component: .custom)
        logger.debug("TransportHandle.updateLocalNodeInfo() - Updating local node info")
        logger.debug("TransportHandle.updateLocalNodeInfo() - NodeInfo CBOR length: \(nodeInfoCbor.count)")
        // Copy handle to local to avoid capturing actor state in closures
        let transportHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            nodeInfoCbor.withUnsafeBytes { raw in
                logger.trace("TransportHandle.updateLocalNodeInfo() - About to call rn_transport_update_local_node_info")
                return rn_transport_update_local_node_info(transportHandle, raw.bindMemory(to: UInt8.self).baseAddress, nodeInfoCbor.count, errPtr)
            }
        }
        logger.debug("TransportHandle.updateLocalNodeInfo() - FFI call completed, code: \(code)")
        if let error = err { 
            logger.error("TransportHandle.updateLocalNodeInfo() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("TransportHandle.updateLocalNodeInfo() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to update local node info") 
        }
        logger.info("TransportHandle.updateLocalNodeInfo() - Local node info updated successfully")
    }
    
    /// Send a request
    /// - Parameter requestCbor: Request data in CBOR format
    /// - Throws: FFIError if request fails
    public func request(requestCbor: Data) async throws {
        let logger = RunarLogger(component: .custom)
        logger.debug("TransportHandle.request() - Sending request")
        logger.debug("TransportHandle.request() - Request CBOR length: \(requestCbor.count)")
        // Copy handle to local to avoid capturing actor state in closures
        let transportHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            requestCbor.withUnsafeBytes { raw in
                logger.trace("TransportHandle.request() - About to call rn_transport_request")
                return rn_transport_request(transportHandle, raw.bindMemory(to: UInt8.self).baseAddress, requestCbor.count, errPtr)
            }
        }
        logger.debug("TransportHandle.request() - FFI call completed, code: \(code)")
        if let error = err { 
            logger.error("TransportHandle.request() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("TransportHandle.request() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to send request") 
        }
        logger.info("TransportHandle.request() - Request sent successfully")
    }
    
    /// Publish an event
    /// - Parameter publishCbor: Event data in CBOR format
    /// - Throws: FFIError if publish fails
    public func publish(publishCbor: Data) async throws {
        let logger = RunarLogger(component: .custom)
        logger.debug("TransportHandle.publish() - Publishing event")
        logger.debug("TransportHandle.publish() - Publish CBOR length: \(publishCbor.count)")
        // Copy handle to local to avoid capturing actor state in closures
        let transportHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            publishCbor.withUnsafeBytes { raw in
                logger.trace("TransportHandle.publish() - About to call rn_transport_publish")
                return rn_transport_publish(transportHandle, raw.bindMemory(to: UInt8.self).baseAddress, publishCbor.count, errPtr)
            }
        }
        logger.debug("TransportHandle.publish() - FFI call completed, code: \(code)")
        if let error = err { 
            logger.error("TransportHandle.publish() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("TransportHandle.publish() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to publish event") 
        }
        logger.info("TransportHandle.publish() - Event published successfully")
    }
    
    /// Complete a request
    /// - Parameter completeCbor: Completion data in CBOR format
    /// - Throws: FFIError if completion fails
    public func completeRequest(completeCbor: Data) async throws {
        let logger = RunarLogger(component: .custom)
        logger.debug("TransportHandle.completeRequest() - Completing request")
        logger.debug("TransportHandle.completeRequest() - Complete CBOR length: \(completeCbor.count)")
        // Copy handle to local to avoid capturing actor state in closures
        let transportHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            completeCbor.withUnsafeBytes { raw in
                logger.trace("TransportHandle.completeRequest() - About to call rn_transport_complete_request")
                return rn_transport_complete_request(transportHandle, raw.bindMemory(to: UInt8.self).baseAddress, completeCbor.count, errPtr)
            }
        }
        logger.debug("TransportHandle.completeRequest() - FFI call completed, code: \(code)")
        if let error = err { 
            logger.error("TransportHandle.completeRequest() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("TransportHandle.completeRequest() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to complete request") 
        }
        logger.info("TransportHandle.completeRequest() - Request completed successfully")
    }
    
    /// Stop the transport
    /// - Throws: FFIError if stop fails
    public func stop() async throws {
        let logger = RunarLogger(component: .custom)
        logger.debug("TransportHandle.stop() - Stopping transport")
        // Copy handle to local to avoid capturing actor state in closures
        let transportHandle = self.handle
        let (code, err) = withRnErrorCode { errPtr in
            logger.trace("TransportHandle.stop() - About to call rn_transport_stop")
            return rn_transport_stop(transportHandle, errPtr)
        }
        logger.debug("TransportHandle.stop() - FFI call completed, code: \(code)")
        if let error = err { 
            logger.error("TransportHandle.stop() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("TransportHandle.stop() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to stop transport") 
        }
        logger.info("TransportHandle.stop() - Transport stopped successfully")
    }
    
    /// Get local address
    /// - Returns: Local address string
    /// - Throws: FFIError if getting address fails
    public func getLocalAddr() async throws -> String {
        let logger = RunarLogger(component: .custom)
        logger.debug("TransportHandle.getLocalAddr() - Getting local address")
        // Copy handle to local to avoid capturing actor state in closures
        let transportHandle = self.handle
        var outStr: UnsafeMutablePointer<CChar>?
        var outLen = 0
        let (code, err) = withRnErrorCode { errPtr in
            logger.trace("TransportHandle.getLocalAddr() - About to call rn_transport_local_addr")
            return rn_transport_local_addr(transportHandle, &outStr, &outLen, errPtr)
        }
        logger.debug("TransportHandle.getLocalAddr() - FFI call completed, code: \(code)")
        if let error = err { 
            logger.error("TransportHandle.getLocalAddr() - FFI error: \(error)")
            throw error 
        }
        guard code == 0 else { 
            logger.error("TransportHandle.getLocalAddr() - FFI operation failed with code: \(code)")
            throw FFIError.operationFailed("Failed to get local address") 
        }
        
        defer {
            if let str = outStr {
                rn_string_free(str)
            }
        }
        
        guard let str = outStr else { 
            logger.debug("TransportHandle.getLocalAddr() - No local address returned")
            throw FFIError.operationFailed("No local address returned") 
        }
        let address = String(cString: str)
        logger.debug("TransportHandle.getLocalAddr() - Local address: \(address)")
        return address
    }
}

// MARK: - Transport Parameter Types


// MARK: - Type Aliases for Backward Compatibility

/// Type alias for backward compatibility with serializer
/// This allows the serializer to continue using EnvelopeCrypto while we transition to CommonKeyManager
public typealias EnvelopeCrypto = CommonKeyManager

public enum FFITypesVectors {
    public static func writeAll(to base: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        // Match Rust example vectors exactly
        let body = EnrollmentTokenBody(
            token_id: "test_token_001",
            network_id: "test_network",
            subject_hint: "test_subject",
            not_before: 1757890822,
            expires_at: 1757894422,
            nonce: Data([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]),
            permissions: ["enroll"]
        )
        try CodableCBOREncoder().encode(body)
            .write(to: base.appendingPathComponent("enrollment_token_body_basic.bin"))

        let token = EnrollmentToken(
            body: body,
            signature: Data([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70]),
            signer_id: "test_signer_001"
        )
        try CodableCBOREncoder().encode(token)
            .write(to: base.appendingPathComponent("enrollment_token_basic.bin"))

        let setup = SetupToken(
            node_id: "test_node_001",
            node_public_key: Array(repeating: 1, count: 65),
            node_agreement_public_key: Array(repeating: 2, count: 65),
            csr_der: Array(repeating: 3, count: 318)
        )
        try CodableCBOREncoder().encode(setup)
            .write(to: base.appendingPathComponent("setup_token_basic.bin"))

        // For CSR request, Rust uses a token with 70 bytes of value 1 for signature
        let tokenForRequest = EnrollmentToken(
            body: body,
            signature: Data(Array(repeating: 1, count: 70)),
            signer_id: "test_signer_001"
        )
        let csrReq = CsrEnrollRequest(
            network_id: "test_network",
            csr_der: Data(Array(repeating: 7, count: 318)),
            enrollment_token: tokenForRequest
        )
        try CodableCBOREncoder().encode(csrReq)
            .write(to: base.appendingPathComponent("csr_enroll_request_basic.bin"))

        // Add response/error vectors to fully validate parity
        let enrollResp = CsrEnrollResponse(
            network_id: "test_network",
            certificate_der: Array(repeating: 9, count: 1024),
            issuing_ca_der: Array(repeating: 10, count: 512),
            root_ca_der: Array(repeating: 11, count: 256),
            expires_at: 1757894422
        )
        try CodableCBOREncoder().encode(enrollResp)
            .write(to: base.appendingPathComponent("csr_enroll_response_basic.bin"))

        let caError = CaErrorResponse(code: "unauthorized", message: "Invalid enrollment token", reason: nil)
        try CodableCBOREncoder().encode(caError)
            .write(to: base.appendingPathComponent("ca_error_response_basic.bin"))
    }
}










