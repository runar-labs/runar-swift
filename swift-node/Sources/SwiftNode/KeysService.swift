import Foundation
import RunarFFI
import RunarSerializer
import SwiftCBOR
import SwiftCommon

// MARK: - Keys Service

/// KeysService handles cryptographic operations and certificate management
/// This service provides the Swift-native interface to FFI cryptographic functions
@MainActor
public final class KeysService: ServiceBase {
    private let nodeId: String
    private var keys: FFIKeys?

    public init(logger: RunarLogger = RunarLogger(component: .keys), nodeId: String) {
        self.nodeId = nodeId
        super.init(name: "$keys", version: "1.0.0", path: "$keys", description: "Cryptographic key management and certificate operations", logger: logger)
    }

    // MARK: - Service Lifecycle

    override public func performInit(_ context: LifecycleContext) async throws {
        networkId = context.networkId

        // Initialize FFI keys if not already provided
        if keys == nil {
            keys = try FFIKeys()
        }
    }

    override public func performStart(_ context: LifecycleContext) async throws {
        // Register all key management actions
        try await registerKeyActions(context: context)
        try await registerCertificateActions(context: context)
        try await registerEncryptionActions(context: context)
    }

    override public func performStop(_: LifecycleContext) async throws {
        keys = nil
    }

    // MARK: - Key Management Actions

    private func registerKeyActions(context: LifecycleContext) async throws {
        // Generate new key pair
        try await context.registerAction("generate_keypair") { [weak self] payload, _ in
            guard let self = self else { throw BaseRunarError.serviceError("KeysService not available", component: .keys) }

            let request = try payload?.asType(KeypairRequest.self) ?? KeypairRequest(algorithm: .ed25519)
            let keypair = try await self.generateKeypair(algorithm: request.algorithm)
            return AnyValue.struct(keypair)
        }

        // Get public key
        try await context.registerAction("get_public_key") { [weak self] _, _ in
            guard let self = self else { throw BaseRunarError.serviceError("KeysService not available", component: .keys) }

            let publicKey = try await self.getPublicKey()
            return AnyValue.struct(publicKey)
        }

        // Get node ID
        try await context.registerAction("get_node_id") { [weak self] _, _ in
            guard let self = self else { throw BaseRunarError.serviceError("KeysService not available", component: .keys) }

            return AnyValue.primitive(self.nodeId)
        }

        // Note: Sign/Verify actions removed - use FFI directly when signing/verification is needed
    }

    // MARK: - Certificate Actions

    private func registerCertificateActions(context: LifecycleContext) async throws {
        // Generate certificate
        try await context.registerAction("generate_certificate") { [weak self] payload, _ in
            guard let self = self else { throw BaseRunarError.serviceError("KeysService not available", component: .keys) }

            guard let certRequest = try payload?.asType(CertificateRequest.self) else {
                throw BaseRunarError.serializationError("Invalid certificate request", component: .keys)
            }

            let certificate = try await self.generateCertificate(request: certRequest)
            return AnyValue.struct(certificate)
        }

        // Validate certificate
        try await context.registerAction("validate_certificate") { [weak self] payload, _ in
            guard let self = self else { throw BaseRunarError.serviceError("KeysService not available", component: .keys) }

            guard let certData = try payload?.asType(Data.self) else {
                throw BaseRunarError.serializationError("Invalid certificate data", component: .keys)
            }

            let validation = try await self.validateCertificate(certificateData: certData)
            return AnyValue.struct(validation)
        }

        // Get certificate chain
        try await context.registerAction("get_certificate_chain") { [weak self] _, _ in
            guard let self = self else { throw BaseRunarError.serviceError("KeysService not available", component: .keys) }

            let chain = try await self.getCertificateChain()
            return AnyValue.struct(chain)
        }
    }

    // MARK: - Encryption Actions

    private func registerEncryptionActions(context: LifecycleContext) async throws {
        // Encrypt data
        try await context.registerAction("encrypt") { [weak self] payload, _ in
            guard let self = self else { throw BaseRunarError.serviceError("KeysService not available", component: .keys) }

            guard let encryptRequest = try payload?.asType(EncryptRequest.self) else {
                throw BaseRunarError.serializationError("Invalid encrypt request", component: .keys)
            }

            let encrypted = try await self.encrypt(data: encryptRequest.data, publicKey: encryptRequest.publicKey)
            return AnyValue.struct(encrypted)
        }

        // Decrypt data
        try await context.registerAction("decrypt") { [weak self] payload, _ in
            guard let self = self else { throw BaseRunarError.serviceError("KeysService not available", component: .keys) }

            guard let decryptRequest = try payload?.asType(DecryptRequest.self) else {
                throw BaseRunarError.serializationError("Invalid decrypt request", component: .keys)
            }

            let decrypted = try await self.decrypt(data: decryptRequest.data)
            return AnyValue.struct(decrypted)
        }

        // Set label mapping for encryption
        try await context.registerAction("set_label_mapping") { [weak self] payload, _ in
            guard let self = self else { throw BaseRunarError.serviceError("KeysService not available", component: .keys) }

            guard let mappingData = try payload?.asType(Data.self) else {
                throw BaseRunarError.serializationError("Invalid label mapping data", component: .keys)
            }

            try await self.setLabelMapping(mappingData: mappingData)
            return AnyValue.primitive(true)
        }
    }

    // MARK: - Key Management Implementation

    public func generateKeypair(algorithm: KeyAlgorithm) async throws -> KeypairResponse {
        guard let keys = keys else {
            throw BaseRunarError.serviceError("Keys not initialized", component: .keys)
        }

        // For now, we'll use the FFI keys that are already generated
        // In the future, this could support generating additional key pairs
        let publicKey = try keys.publicKey()
        let nodeId = try keys.nodeId()

        return KeypairResponse(
            publicKey: publicKey,
            nodeId: nodeId,
            algorithm: algorithm
        )
    }

    public func getPublicKey() async throws -> PublicKeyResponse {
        guard let keys = keys else {
            throw BaseRunarError.serviceError("Keys not initialized", component: .keys)
        }

        let publicKey = try keys.publicKey()
        return PublicKeyResponse(publicKey: publicKey)
    }

    // Note: Sign/Verify methods removed - use FFI directly when signing/verification is needed

    // MARK: - Certificate Management Implementation

    public func generateCertificate(request: CertificateRequest) async throws -> CertificateResponse {
        guard let keys = keys else {
            throw BaseRunarError.serviceError("Keys not initialized", component: .keys)
        }

        // Generate a self-signed certificate using Swift Certificates
        // This is a placeholder implementation - in production you'd integrate with
        // the Swift Certificates library for proper certificate generation

        let certificateData = try await generateSelfSignedCertificate(request: request)

        return CertificateResponse(
            certificate: certificateData,
            serialNumber: generateSerialNumber(),
            validFrom: Date(),
            validUntil: Date().addingTimeInterval(request.validityDays * 24 * 60 * 60)
        )
    }

    public func validateCertificate(certificateData: Data) async throws -> CertificateValidationResponse {
        // Placeholder validation - in production, use Swift Certificates for proper validation
        let isValid = try validateCertificateFormat(certificateData)

        return CertificateValidationResponse(
            isValid: isValid,
            issuer: "Self-Signed",
            subject: "Runar Node",
            validFrom: Date(),
            validUntil: Date().addingTimeInterval(365 * 24 * 60 * 60),
            serialNumber: "123456789"
        )
    }

    public func getCertificateChain() async throws -> CertificateChainResponse {
        guard let keys = keys else {
            throw BaseRunarError.serviceError("Keys not initialized", component: .keys)
        }

        // For now, return a simple chain with the node's certificate
        // In production, this would return the full certificate chain
        let publicKey = try keys.publicKey()

        return CertificateChainResponse(
            certificates: [publicKey], // Using public key as certificate for now
            rootCertificate: publicKey
        )
    }

    // MARK: - Encryption Implementation

    public func encrypt(data: Data, publicKey _: Data) async throws -> EncryptionResponse {
        guard let keys = keys else {
            throw BaseRunarError.serviceError("Keys not initialized", component: .keys)
        }

        // Use FFI local encryption (placeholder until proper public key encryption is available)
        let encrypted = try keys.encryptLocalData(data)
        return EncryptionResponse(encryptedData: encrypted)
    }

    public func decrypt(data: Data) async throws -> DecryptionResponse {
        guard let keys = keys else {
            throw BaseRunarError.serviceError("Keys not initialized", component: .keys)
        }

        // Use FFI local decryption
        let decrypted = try keys.decryptLocalData(data)
        return DecryptionResponse(decryptedData: decrypted)
    }

    public func setLabelMapping(mappingData: Data) async throws {
        guard let keys = keys else {
            throw BaseRunarError.serviceError("Keys not initialized", component: .keys)
        }

        try keys.setLabelMapping(mappingData)
    }

    // MARK: - Private Implementation Methods

    private func generateSelfSignedCertificate(request: CertificateRequest) async throws -> Data {
        // Placeholder implementation - in production, use Swift Certificates
        // to generate proper X.509 certificates

        // For now, we'll create a simple CBOR-encoded certificate structure
        let certMap: [CBOR: CBOR] = try [
            .utf8String("version"): .unsignedInt(3),
            .utf8String("serialNumber"): .utf8String(generateSerialNumber()),
            .utf8String("subject"): .utf8String(request.subject),
            .utf8String("issuer"): .utf8String(request.issuer),
            .utf8String("validFrom"): .utf8String(ISO8601DateFormatter().string(from: Date())),
            .utf8String("validUntil"): .utf8String(ISO8601DateFormatter().string(from: Date().addingTimeInterval(request.validityDays * 24 * 60 * 60))),
            .utf8String("publicKey"): .byteString([UInt8](keys?.publicKey() ?? Data()))
        ]

        return Data(CBOR.map(certMap).encode())
    }

    private func validateCertificateFormat(_ certificateData: Data) throws -> Bool {
        // Placeholder validation - check if it's valid CBOR
        do {
            _ = try CBORDecoder(input: [UInt8](certificateData)).decodeItem()
            return true
        } catch {
            return false
        }
    }

    private func generateSerialNumber() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
    }
}

// MARK: - Request/Response Types

public struct KeypairRequest: Codable, Sendable {
    public let algorithm: KeyAlgorithm

    public init(algorithm: KeyAlgorithm) {
        self.algorithm = algorithm
    }
}

public enum KeyAlgorithm: String, Codable, Sendable {
    case ed25519
    case secp256k1
    case rsa2048
}

public struct KeypairResponse: Codable, Sendable {
    public let publicKey: Data
    public let nodeId: String
    public let algorithm: KeyAlgorithm

    public init(publicKey: Data, nodeId: String, algorithm: KeyAlgorithm) {
        self.publicKey = publicKey
        self.nodeId = nodeId
        self.algorithm = algorithm
    }
}

public struct PublicKeyResponse: Codable, Sendable {
    public let publicKey: Data

    public init(publicKey: Data) {
        self.publicKey = publicKey
    }
}

public struct CertificateRequest: Codable, Sendable {
    public let subject: String
    public let issuer: String
    public let validityDays: TimeInterval
    public let keyUsage: [String]?

    public init(subject: String = "Runar Node", issuer: String = "Runar CA", validityDays: TimeInterval = 365, keyUsage: [String]? = nil) {
        self.subject = subject
        self.issuer = issuer
        self.validityDays = validityDays
        self.keyUsage = keyUsage
    }
}

public struct CertificateResponse: Codable, Sendable {
    public let certificate: Data
    public let serialNumber: String
    public let validFrom: Date
    public let validUntil: Date

    public init(certificate: Data, serialNumber: String, validFrom: Date, validUntil: Date) {
        self.certificate = certificate
        self.serialNumber = serialNumber
        self.validFrom = validFrom
        self.validUntil = validUntil
    }
}

public struct CertificateValidationResponse: Codable, Sendable {
    public let isValid: Bool
    public let issuer: String
    public let subject: String
    public let validFrom: Date
    public let validUntil: Date
    public let serialNumber: String

    public init(isValid: Bool, issuer: String, subject: String, validFrom: Date, validUntil: Date, serialNumber: String) {
        self.isValid = isValid
        self.issuer = issuer
        self.subject = subject
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.serialNumber = serialNumber
    }
}

public struct CertificateChainResponse: Codable, Sendable {
    public let certificates: [Data]
    public let rootCertificate: Data

    public init(certificates: [Data], rootCertificate: Data) {
        self.certificates = certificates
        self.rootCertificate = rootCertificate
    }
}

public struct EncryptRequest: Codable, Sendable {
    public let data: Data
    public let publicKey: Data

    public init(data: Data, publicKey: Data) {
        self.data = data
        self.publicKey = publicKey
    }
}

public struct EncryptionResponse: Codable, Sendable {
    public let encryptedData: Data

    public init(encryptedData: Data) {
        self.encryptedData = encryptedData
    }
}

public struct DecryptRequest: Codable, Sendable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }
}

public struct DecryptionResponse: Codable, Sendable {
    public let decryptedData: Data

    public init(decryptedData: Data) {
        self.decryptedData = decryptedData
    }
}
