import Foundation
import CRunarFFI

// MARK: - Envelope Decryption Functions Extension

@available(macOS 11.0, *)
extension KeysFFI {
    
    /// Node: Decrypt envelope using node's keys
    public func nodeDecryptEnvelope(eedCbor: Data) throws -> Data {
        let manager = try validateNodeManager()
        return try manager.decryptEnvelope(eedCbor: eedCbor)
    }

    /// Mobile: Decrypt envelope using mobile's keys
    public func mobileDecryptEnvelope(eedCbor: Data) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.decryptEnvelope(eedCbor: eedCbor)
    }
}
