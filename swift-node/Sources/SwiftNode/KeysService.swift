import Foundation
import RunarFFI
import RunarSerializer
import SwiftCommon

// MARK: - Keys Service

/// KeysService handles cryptographic operations via FFI
/// This service manages key management, certificate operations, and encryption
@MainActor
public final class KeysService: ServiceBase {
    private let nodeId: String
    private var keys: FFIKeys?

    public init(logger: RunarLogger = RunarLogger(component: .keys), nodeId: String) {
        self.nodeId = nodeId
        super.init(name: "$keys", version: "1.0.0", path: "$keys", description: "Cryptographic operations service", logger: logger)
    }

    // MARK: - Service Lifecycle

    override public func performInitService(_ context: LifecycleContext) async throws {
        if keys == nil {
            keys = try FFIKeys()
        }
    }

    override public func performStart(_ context: LifecycleContext) async throws {
        // Register the only action that exists in Rust: ensure_symmetric_key
        try await registerEnsureSymmetricKeyAction(context: context)
    }

    override public func performStop(_: LifecycleContext) async throws {
        keys = nil
    }

    // MARK: - Key Management Actions

    private func registerEnsureSymmetricKeyAction(context: LifecycleContext) async throws {
        // Register the only action that exists in Rust: ensure_symmetric_key
        try await context.registerAction("ensure_symmetric_key") { [weak self] payload, _ in
            guard let self = self else { throw BaseRunarError.serviceError("KeysService not available", component: .keys) }

            // Parse the key_name parameter from payload
            guard let keyName = try await payload?.asType() as String? else {
                throw BaseRunarError.serializationError("key_name parameter is required and must be a string", component: .keys)
            }

            let response = try await self.ensureSymmetricKey(keyName: keyName)
            return AnyValue.struct(response)
        }
    }

    // MARK: - Symmetric Key Implementation

    private func ensureSymmetricKey(keyName: String) async throws -> SymmetricKeyResponse {
        guard keys != nil else {
            throw BaseRunarError.serviceError("Keys not initialized", component: .keys)
        }
        
        // Use FFI to ensure symmetric key exists
        // This would call the appropriate FFI method to ensure the key exists
        // For now, return a basic response structure
        return SymmetricKeyResponse(
            keyName: keyName,
            keyData: Data(), // Would be filled by FFI call
            created: true
        )
    }

    // MARK: - Public API (for other services)

    public func getPublicKey() async throws -> PublicKeyResponse {
        guard let keys = keys else {
            throw BaseRunarError.serviceError("Keys not initialized", component: .keys)
        }
        
        let publicKey = try keys.publicKey()
        return PublicKeyResponse(publicKey: publicKey)
    }
}

// MARK: - Request/Response Types

public struct SymmetricKeyResponse: Codable, Sendable {
    public let keyName: String
    public let keyData: Data
    public let created: Bool

    public init(keyName: String, keyData: Data, created: Bool) {
        self.keyName = keyName
        self.keyData = keyData
        self.created = created
    }
}

public struct PublicKeyResponse: Codable, Sendable {
    public let publicKey: Data

    public init(publicKey: Data) {
        self.publicKey = publicKey
    }
}
