import Foundation
import CRunarFFI

// MARK: - Message Encryption Functions Extension

@available(macOS 11.0, *)
extension KeysFFI {

    /// Mobile: Decrypt message from node using mobile's agreement private key
    public func mobileDecryptMessageFromNode(encryptedMessage: Data) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.decryptMessageFromNode(encryptedMessage: encryptedMessage)
    }

    /// Node: Decrypt message from mobile using node's agreement private key
    public func decryptMessageFromMobile(encryptedMessage: Data) throws -> Data {
        let manager = try validateNodeManager()
        return try manager.decryptMessageFromMobile(encryptedMessage: encryptedMessage)
    }
}
