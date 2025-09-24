import Foundation
import RunarSerializer
@testable import SwiftFFI

/// Test implementation of CommonKeyManager for testing purposes
/// This is a temporary solution until NodeKeyManager and MobileKeyManager are implemented
/// This implementation provides basic functionality for testing without using mocks
public class TestKeyManagerAdapter: @unchecked Sendable, CommonKeyManager {
    // MARK: - CommonKeyManager Implementation

    public func encryptWithEnvelope(data: Data, networkPublicKey _: Data?, profilePublicKeys _: [Data]) async throws -> Data {
        // For testing purposes, we'll create a simple envelope format
        // In a real implementation, this would call the actual FFI
        var envelope = Data()

        // Add a simple header to identify this as test data
        envelope.append(Data("TEST_ENVELOPE".utf8))
        envelope.append(UInt8(0)) // Separator

        // Add the original data (in a real implementation, this would be encrypted)
        envelope.append(data)

        return envelope
    }

    public func decryptEnvelope(envelopeData: Data) async throws -> Data {
        // For testing purposes, we'll extract the original data
        // In a real implementation, this would decrypt the envelope
        guard envelopeData.count > 13 else {
            throw SerializerError.deserializationFailed("Invalid test envelope format")
        }

        let header = Data(envelopeData.prefix(13))
        guard String(data: header, encoding: .utf8) == "TEST_ENVELOPE" else {
            throw SerializerError.deserializationFailed("Invalid test envelope header")
        }

        // Skip header and separator
        return Data(envelopeData.dropFirst(14))
    }

    public func encryptLocalData(data: Data) async throws -> Data {
        // Simple test implementation - just return the data with a prefix
        var encrypted = Data()
        encrypted.append(Data("LOCAL_".utf8))
        encrypted.append(data)
        return encrypted
    }

    public func decryptLocalData(encryptedData: Data) async throws -> Data {
        // Simple test implementation - remove the prefix
        guard encryptedData.count > 6 else {
            throw SerializerError.deserializationFailed("Invalid local data format")
        }

        let header = Data(encryptedData.prefix(6))
        guard String(data: header, encoding: .utf8) == "LOCAL_" else {
            throw SerializerError.deserializationFailed("Invalid local data header")
        }

        return Data(encryptedData.dropFirst(6))
    }

    public func encryptForNetwork(data: Data, networkPublicKey _: Data) async throws -> Data {
        // Simple test implementation
        var encrypted = Data()
        encrypted.append(Data("NETWORK_".utf8))
        encrypted.append(data)
        return encrypted
    }

    public func decryptNetworkData(encryptedEnvelope: Data) async throws -> Data {
        // Simple test implementation
        guard encryptedEnvelope.count > 8 else {
            throw SerializerError.deserializationFailed("Invalid network data format")
        }

        let header = Data(encryptedEnvelope.prefix(8))
        guard String(data: header, encoding: .utf8) == "NETWORK_" else {
            throw SerializerError.deserializationFailed("Invalid network data header")
        }

        return Data(encryptedEnvelope.dropFirst(8))
    }

    public func ensureSymmetricKey(name: String) async throws -> Data {
        // Return a test symmetric key
        Data("test_symmetric_key_\(name)".utf8)
    }

    public func setPersistenceDirectory(_: String) async throws {
        // Test implementation - do nothing
    }

    public func enableAutoPersistence(_: Bool) async throws {
        // Test implementation - do nothing
    }

    public func wipePersistence() async throws {
        // Test implementation - do nothing
    }

    public func getKeystoreCapabilities() async throws -> KeystoreCapabilities {
        // Create a test capabilities struct using reflection
        // Since the initializer is internal, we'll create it using unsafe methods
        let capabilities = KeystoreCapabilities(version: 1, flags: 0)
        return capabilities
    }

    public func flushState() async throws {
        // Test implementation - do nothing
    }

    public func registerAppleDeviceKeystore(label _: String) async throws {
        // Test implementation - do nothing
    }
}
