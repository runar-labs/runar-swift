import Foundation

// MARK: - Type Definitions

/// Node Info structure for FFI
public struct RunarFFINodeInfo {
    public let nodeId: String
    public let publicKey: Data
}

/// Envelope encrypted data structure
public struct EnvelopeEncryptedData {
    public let data: Data
    public let networkPublicKey: Data?
    public let profileKeys: [Data]
    
    public init(data: Data, networkPublicKey: Data? = nil, profileKeys: [Data] = []) {
        self.data = data
        self.networkPublicKey = networkPublicKey
        self.profileKeys = profileKeys
    }
}

/// Envelope crypto protocol for encryption/decryption
public protocol EnvelopeCrypto {
    func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profileKeys: [Data]) throws -> Data
    func decryptEnvelope(eedCbor: Data) throws -> Data
}

/// Atomic wrapper for thread-safe access
public final class Atomic<T> {
    private var value: T
    private let lock = NSLock()

    public init(_ value: T) {
        self.value = value
    }

    public func load() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func store(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

// MARK: - Protocols

/// Mobile Key Manager - mirrors Rust MobileKeyManager
public protocol MobileKeyManager {
    func initializeUserRootKey() throws
    func getUserPublicKey() throws -> Data
    func processSetupToken(setupTokenCBOR: Data) throws -> Data
    func registerDeviceKeystore(_ keystore: DeviceKeystoreType) throws
    func getKeystoreState() throws -> Int32
    func generateNetworkDataKey() throws -> Data
    func createNetworkKeyMessage(networkPublicKey: Data, nodeAgreementPk: Data) throws -> Data
    func deriveUserProfileKey(label: String) throws -> Data
    func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profileKeys: [Data]?) throws -> Data
    func decryptMessageFromNode(encryptedMessage: Data) throws -> Data
    func decryptEnvelope(eedCbor: Data) throws -> Data
    func installNetworkPublicKey(networkPublicKey: Data) throws
}

/// Node Key Manager - mirrors Rust NodeKeyManager
public protocol NodeKeyManager {
    func getPublicKey() throws -> Data
    func getAgreementPublicKey() throws -> Data
    func generateCSR() throws -> Data
    func installCertificate(_ nodeCertificateMessageCBOR: Data) throws
    func registerDeviceKeystore(_ keystore: DeviceKeystoreType) throws
    func getKeystoreState() throws -> Int32
    func installNetworkKey(_ nkmCbor: Data) throws
    func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profileKeys: [Data]?) throws -> Data
    func encryptLocalData(_ data: Data) throws -> Data
    func decryptLocalData(_ encrypted: Data) throws -> Data
    func decryptMessageFromMobile(encryptedMessage: Data) throws -> Data
    func decryptEnvelope(eedCbor: Data) throws -> Data
    func getNodeId() throws -> String
}

/// Label Resolver for key derivation
public protocol LabelResolver {
    func resolveLabel(_ label: String) throws -> String
}

/// Device Keystore abstraction
public protocol DeviceKeystore {
    func storeKey(_ key: Data, label: String) throws
    func retrieveKey(label: String) throws -> Data?
    func deleteKey(label: String) throws
}
