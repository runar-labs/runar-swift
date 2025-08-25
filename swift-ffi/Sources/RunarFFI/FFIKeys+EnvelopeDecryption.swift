import CRunarFFI
import Foundation

// MARK: - Envelope Decryption Functions Extension

@available(macOS 11.0, *)
public extension KeysFFI {
    /// Node: Decrypt envelope using node's keys
    func nodeDecryptEnvelope(eedCbor: Data) throws -> Data {
        let manager = try validateNodeManager()
        return try manager.decryptEnvelope(eedCbor: eedCbor)
    }

    /// Mobile: Decrypt envelope using mobile's keys
    func mobileDecryptEnvelope(eedCbor: Data) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.decryptEnvelope(eedCbor: eedCbor)
    }
}
