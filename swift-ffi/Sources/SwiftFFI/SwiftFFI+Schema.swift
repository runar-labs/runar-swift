//
//  SwiftFFI+Schema.swift
//  SwiftFFI
//
//  CBOR Schema Types
//  This file contains all CBOR-related Codable structs and enums
//  that are used for serialization/deserialization with the Rust FFI layer.
//

import Foundation
import SwiftCBOR
import SwiftCommon

// MARK: - CA Client Types

public struct EnrollmentToken: Codable, Equatable, Sendable {
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

public struct EnrollmentTokenBody: Codable, Equatable, Sendable {
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

public struct SetupToken: Codable, Equatable, Sendable {
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
        // Convert CBOR to Data and use proper CodableCBORDecoder
        let cborData = Data(cbor.encode())
        let decoder = CodableCBORDecoder()
        let setupToken = try decoder.decode(SetupToken.self, from: cborData)

        node_id = setupToken.node_id
        node_public_key = setupToken.node_public_key
        node_agreement_public_key = setupToken.node_agreement_public_key
        csr_der = setupToken.csr_der
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

public struct CsrEnrollRequest: Codable, Equatable, Sendable {
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

public struct CsrEnrollResponse: Codable, Equatable, Sendable {
    public let network_id: String
    public let certificate_der: Data
    public let issuing_ca_der: Data
    public let root_ca_der: Data?
    public let expires_at: UInt64

    enum CodingKeys: String, CodingKey {
        case network_id
        case certificate_der
        case issuing_ca_der
        case root_ca_der
        case expires_at
    }

    public init(network_id: String, certificate_der: Data, issuing_ca_der: Data, root_ca_der: Data? = nil, expires_at: UInt64) {
        self.network_id = network_id
        self.certificate_der = certificate_der
        self.issuing_ca_der = issuing_ca_der
        self.root_ca_der = root_ca_der
        self.expires_at = expires_at
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        network_id = try container.decode(String.self, forKey: .network_id)
        certificate_der = try container.decode(Data.self, forKey: .certificate_der)
        issuing_ca_der = try container.decode(Data.self, forKey: .issuing_ca_der)
        root_ca_der = try container.decodeIfPresent(Data.self, forKey: .root_ca_der)
        expires_at = try container.decode(UInt64.self, forKey: .expires_at)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network_id, forKey: .network_id)
        try container.encode(certificate_der, forKey: .certificate_der)
        try container.encode(issuing_ca_der, forKey: .issuing_ca_der)
        try container.encodeIfPresent(root_ca_der, forKey: .root_ca_der)
        try container.encode(expires_at, forKey: .expires_at)
    }
}

public struct RenewResponse: Codable, Equatable, Sendable {
    public let network_id: String
    public let certificate_der: Data
    public let issuing_ca_der: Data
    public let expires_at: UInt64

    enum CodingKeys: String, CodingKey {
        case network_id
        case certificate_der
        case issuing_ca_der
        case expires_at
    }

    public init(network_id: String, certificate_der: Data, issuing_ca_der: Data, expires_at: UInt64) {
        self.network_id = network_id
        self.certificate_der = certificate_der
        self.issuing_ca_der = issuing_ca_der
        self.expires_at = expires_at
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        network_id = try container.decode(String.self, forKey: .network_id)
        certificate_der = try container.decode(Data.self, forKey: .certificate_der)
        issuing_ca_der = try container.decode(Data.self, forKey: .issuing_ca_der)
        expires_at = try container.decode(UInt64.self, forKey: .expires_at)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network_id, forKey: .network_id)
        try container.encode(certificate_der, forKey: .certificate_der)
        try container.encode(issuing_ca_der, forKey: .issuing_ca_der)
        try container.encode(expires_at, forKey: .expires_at)
    }
}

public struct ChainResponse: Codable, Equatable, Sendable {
    public let network_id: String
    public let issuing_ca_der: Data
    public let root_ca_der: Data?

    enum CodingKeys: String, CodingKey {
        case network_id
        case issuing_ca_der
        case root_ca_der
    }

    public init(network_id: String, issuing_ca_der: Data, root_ca_der: Data? = nil) {
        self.network_id = network_id
        self.issuing_ca_der = issuing_ca_der
        self.root_ca_der = root_ca_der
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        network_id = try container.decode(String.self, forKey: .network_id)
        issuing_ca_der = try container.decode(Data.self, forKey: .issuing_ca_der)
        root_ca_der = try container.decodeIfPresent(Data.self, forKey: .root_ca_der)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network_id, forKey: .network_id)
        try container.encode(issuing_ca_der, forKey: .issuing_ca_der)
        try container.encodeIfPresent(root_ca_der, forKey: .root_ca_der)
    }
}

public struct CaErrorResponse: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let reason: String?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case reason
    }
}

public struct RenewRequest: Codable, Equatable, Sendable {
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

// MARK: - CA Configuration Types

public struct CaServerConfig: Codable, Equatable, Sendable {
    public let bootstrapBind: String
    public let authenticatedBind: String
    public let networkId: String
    public let rateLimitPerMinute: Int
    public let rateLimitPerHour: Int

    public init(bootstrapBind: String, authenticatedBind: String, networkId: String, rateLimitPerMinute: Int, rateLimitPerHour: Int) {
        self.bootstrapBind = bootstrapBind
        self.authenticatedBind = authenticatedBind
        self.networkId = networkId
        self.rateLimitPerMinute = rateLimitPerMinute
        self.rateLimitPerHour = rateLimitPerHour
    }

    private enum CodingKeys: String, CodingKey {
        case bootstrapBind = "bootstrap_bind"
        case authenticatedBind = "authenticated_bind"
        case networkId = "network_id"
        case rateLimitPerMinute = "rate_limit_per_minute"
        case rateLimitPerHour = "rate_limit_per_hour"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bootstrapBind, forKey: .bootstrapBind)
        try container.encode(authenticatedBind, forKey: .authenticatedBind)
        try container.encode(networkId, forKey: .networkId)
        try container.encode(rateLimitPerMinute, forKey: .rateLimitPerMinute)
        try container.encode(rateLimitPerHour, forKey: .rateLimitPerHour)
    }
}

public struct CaClientConfigAll: Codable, Equatable, Sendable {
    public let bootstrap_server: String
    public let authenticated_server: String
    public let network_id: String
    public let request_timeout_seconds: Int
    public let max_retries: Int
    public let root_ca_der: [UInt8]
    public let issuing_ca_der: [UInt8]

    public init(bootstrap_server: String, authenticated_server: String, network_id: String, request_timeout_seconds: Int, max_retries: Int, root_ca_der: [UInt8], issuing_ca_der: [UInt8]) throws {
        // Validate that certificates are not empty
        guard !root_ca_der.isEmpty else {
            throw FFIError.operationFailed("root_ca_der cannot be empty")
        }
        guard !issuing_ca_der.isEmpty else {
            throw FFIError.operationFailed("issuing_ca_der cannot be empty")
        }

        self.bootstrap_server = bootstrap_server
        self.authenticated_server = authenticated_server
        self.network_id = network_id
        self.request_timeout_seconds = request_timeout_seconds
        self.max_retries = max_retries
        self.root_ca_der = root_ca_der
        self.issuing_ca_der = issuing_ca_der
    }
}

public struct CustomCaServerConfig: Codable, Equatable, Sendable {
    public let bootstrap_bind: String
    public let authenticated_bind: String
    public let network_id: String
    public let rate_limit_per_minute: Int
    public let rate_limit_per_hour: Int

    public init(bootstrap_bind: String, authenticated_bind: String, network_id: String, rate_limit_per_minute: Int, rate_limit_per_hour: Int) {
        self.bootstrap_bind = bootstrap_bind
        self.authenticated_bind = authenticated_bind
        self.network_id = network_id
        self.rate_limit_per_minute = rate_limit_per_minute
        self.rate_limit_per_hour = rate_limit_per_hour
    }
}

public struct RevokeRequest: Codable, Equatable, Sendable {
    public let network_id: String
    public let certificate_serial: Data
    public let reason: String

    public init(network_id: String, certificate_serial: Data, reason: String) {
        self.network_id = network_id
        self.certificate_serial = certificate_serial
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case network_id
        case certificate_serial
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network_id = try container.decode(String.self, forKey: .network_id)
        certificate_serial = try container.decode(Data.self, forKey: .certificate_serial)
        reason = try container.decode(String.self, forKey: .reason)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network_id, forKey: .network_id)
        try container.encode(certificate_serial, forKey: .certificate_serial)
        try container.encode(reason, forKey: .reason)
    }
}

public struct RevokeResponse: Codable, Equatable, Sendable {
    public let network_id: String
    public let ok: Bool

    public init(network_id: String, ok: Bool) {
        self.network_id = network_id
        self.ok = ok
    }
}

public struct CaStatus: Codable, Equatable, Sendable {
    public let network_id: String
    public let issuing_subject: String
    public let issuing_serial_hex: String
    public let not_before: UInt64
    public let not_after: UInt64

    public init(network_id: String, issuing_subject: String, issuing_serial_hex: String, not_before: UInt64, not_after: UInt64) {
        self.network_id = network_id
        self.issuing_subject = issuing_subject
        self.issuing_serial_hex = issuing_serial_hex
        self.not_before = not_before
        self.not_after = not_after
    }

    enum CodingKeys: String, CodingKey {
        case network_id
        case issuing_subject
        case issuing_serial_hex
        case not_before
        case not_after
    }
}

public struct NetworkMessagePayloadItem: Codable, Equatable, Sendable {
    /// The path/topic associated with this payload
    public let path: String

    /// The serialized value/payload data as bytes
    public let payloadBytes: Data

    /// Correlation ID
    public let correlationId: String

    /// Network public key for encryption context
    public let networkPublicKey: Data?

    /// Profile public keys
    public let profilePublicKeys: [Data]

    public init(path: String, payloadBytes: Data, correlationId: String, networkPublicKey: Data? = nil, profilePublicKeys: [Data] = []) {
        self.path = path
        self.payloadBytes = payloadBytes
        self.correlationId = correlationId
        self.networkPublicKey = networkPublicKey
        self.profilePublicKeys = profilePublicKeys
    }

    enum CodingKeys: String, CodingKey {
        case path
        case payloadBytes = "payload_bytes"
        case correlationId = "correlation_id"
        case networkPublicKey = "network_public_key"
        case profilePublicKeys = "profile_public_keys"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(payloadBytes, forKey: .payloadBytes)
        try container.encode(correlationId, forKey: .correlationId)
        try container.encodeIfPresent(networkPublicKey, forKey: .networkPublicKey)

        // Encode profilePublicKeys as array of Data (which will be encoded as byte strings)
        try container.encode(profilePublicKeys, forKey: .profilePublicKeys)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        payloadBytes = try container.decode(Data.self, forKey: .payloadBytes)
        correlationId = try container.decode(String.self, forKey: .correlationId)
        networkPublicKey = try container.decodeIfPresent(Data.self, forKey: .networkPublicKey)
        profilePublicKeys = try container.decode([Data].self, forKey: .profilePublicKeys)
    }
}

/// Swift representation of NetworkMessage structure from Rust
public struct NetworkMessage: Codable, Equatable, Sendable {
    /// Source node identifier
    public let sourceNodeId: String

    /// Destination node identifier (MUST be specified)
    public let destinationNodeId: String

    /// Message type (Request, Response, Event, etc.)
    public let messageType: UInt32

    /// Single payload for this message
    public let payload: NetworkMessagePayloadItem

    public init(sourceNodeId: String, destinationNodeId: String, messageType: UInt32, payload: NetworkMessagePayloadItem) {
        self.sourceNodeId = sourceNodeId
        self.destinationNodeId = destinationNodeId
        self.messageType = messageType
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case sourceNodeId = "source_node_id"
        case destinationNodeId = "destination_node_id"
        case messageType = "message_type"
        case payload
    }
}

// MARK: - Handshake Structures

/// Connection role for handshake process
public enum ConnectionRole: String, Codable, Sendable, Equatable {
    case initiator = "Initiator"
    case responder = "Responder"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            switch intValue {
            case 0: self = .initiator
            case 1: self = .responder
            default: throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid ConnectionRole value: \(intValue)"))
            }
        } else if let stringValue = try? container.decode(String.self) {
            self = ConnectionRole(rawValue: stringValue) ?? .initiator
        } else {
            throw DecodingError.typeMismatch(ConnectionRole.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int or String for ConnectionRole"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .initiator: try container.encode(0)
        case .responder: try container.encode(1)
        }
    }
}

/// Handshake data exchanged during peer connection
public struct HandshakeData: Codable, Sendable, Equatable {
    /// Node information for the connecting peer
    public let nodeInfo: NodeInfo

    /// Nonce for handshake process
    public let nonce: UInt64

    /// Role of the peer in the connection
    public let role: ConnectionRole

    public init(nodeInfo: NodeInfo, nonce: UInt64, role: ConnectionRole) {
        self.nodeInfo = nodeInfo
        self.nonce = nonce
        self.role = role
    }

    enum CodingKeys: String, CodingKey {
        case nodeInfo = "node_info"
        case nonce
        case role
    }
}

// MARK: - CBOR Structures for Transport

/// Swift representation of NodeInfo structure from Rust
public struct NodeInfo: Codable, Equatable, Sendable {
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
        case nodePublicKey = "node_public_key" // Keep original field name for encoding
        case networkIds = "network_ids"
        case addresses
        case nodeMetadata = "node_metadata"
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try to decode nodePublicKey - handle both field names for compatibility
        let nodePublicKeyArray: [UInt8]
        if let nodePublicKeyData = try? container.decode([UInt8].self, forKey: .nodePublicKey) {
            nodePublicKeyArray = nodePublicKeyData
        } else {
            // Try alternative field name "public_key" (used in PeerDiscovered events)
            let altContainer = try decoder.container(keyedBy: AlternativeCodingKeys.self)
            nodePublicKeyArray = try altContainer.decode([UInt8].self, forKey: .nodePublicKey)
        }
        nodePublicKey = Data(nodePublicKeyArray)

        // Handle missing fields gracefully for PeerDiscovered events
        networkIds = try container.decodeIfPresent([String].self, forKey: .networkIds) ?? []
        addresses = try container.decodeIfPresent([String].self, forKey: .addresses) ?? []
        nodeMetadata = try container.decodeIfPresent(NodeMetadata.self, forKey: .nodeMetadata) ?? NodeMetadata(services: [], subscriptions: [])
        version = try container.decodeIfPresent(Int64.self, forKey: .version) ?? 1
    }

    // Alternative coding keys for compatibility with different field names
    private enum AlternativeCodingKeys: String, CodingKey {
        case nodePublicKey = "public_key"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode nodePublicKey as array of bytes
        try container.encode(Array(nodePublicKey), forKey: .nodePublicKey)
        try container.encode(networkIds, forKey: .networkIds)
        try container.encode(addresses, forKey: .addresses)
        try container.encode(nodeMetadata, forKey: .nodeMetadata)
        try container.encode(version, forKey: .version)
    }
}

/// Swift representation of NodeMetadata structure from Rust
public struct NodeMetadata: Codable, Equatable, Sendable {
    public let services: [ServiceMetadata]
    public let subscriptions: [SubscriptionMetadata]

    public init(services: [ServiceMetadata], subscriptions: [SubscriptionMetadata]) {
        self.services = services
        self.subscriptions = subscriptions
    }
}

/// Swift representation of ServiceMetadata structure from Rust
public struct ServiceMetadata: Codable, Equatable, Sendable {
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
public struct ActionMetadata: Codable, Equatable, Sendable {
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
public struct SubscriptionMetadata: Codable, Equatable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

/// Swift representation of FieldSchema structure from Rust
public struct FieldSchema: Codable, Equatable, Sendable {
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
public enum SchemaDataType: String, Codable, Equatable, Sendable {
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
public struct FFIQuicTransportOptions: Codable, Equatable, Sendable {
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

/// Swift-layer transport options (normalized structure)
public struct QuicTransportOptions: Codable, Sendable {
    // Swift layer options
    public let requestTimeoutSeconds: UInt64

    // FFI options (normalized directly into this struct)
    public let bindAddr: String?
    public let handshakeTimeoutMs: UInt64?
    public let openStreamTimeoutMs: UInt64?
    public let maxMessageSize: UInt64?
    public let responseCacheTtlMs: UInt64?
    public let maxRequestRetries: UInt32?

    public init(
        requestTimeoutSeconds: UInt64 = 30,
        bindAddr: String? = nil,
        handshakeTimeoutMs: UInt64? = nil,
        openStreamTimeoutMs: UInt64? = nil,
        maxMessageSize: UInt64? = nil,
        responseCacheTtlMs: UInt64? = nil,
        maxRequestRetries: UInt32? = nil
    ) {
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.bindAddr = bindAddr
        self.handshakeTimeoutMs = handshakeTimeoutMs
        self.openStreamTimeoutMs = openStreamTimeoutMs
        self.maxMessageSize = maxMessageSize
        self.responseCacheTtlMs = responseCacheTtlMs
        self.maxRequestRetries = maxRequestRetries
    }

    /// Create FFIQuicTransportOptions from this QuicTransportOptions
    /// This is used internally to convert to FFI format
    func toFFIOptions() -> FFIQuicTransportOptions {
        return FFIQuicTransportOptions(
            bindAddr: bindAddr,
            handshakeTimeoutMs: handshakeTimeoutMs,
            openStreamTimeoutMs: openStreamTimeoutMs,
            maxMessageSize: maxMessageSize,
            responseCacheTtlMs: responseCacheTtlMs,
            maxRequestRetries: maxRequestRetries
        )
    }
}

public struct TransportRequestParams: Codable, Equatable {
    public let path: String
    public let correlationId: String
    public let payload: Data // Vec<u8> in Rust
    public let destPeerId: String
    public let networkPublicKey: Data? // Option<Vec<u8>> in Rust
    public let profilePublicKeys: [Data] // Vec<Vec<u8>> in Rust

    public init(path: String, correlationId: String, payload: Data, destPeerId: String, networkPublicKey: Data? = nil, profilePublicKeys: [Data] = []) {
        self.path = path
        self.correlationId = correlationId
        self.payload = payload
        self.destPeerId = destPeerId
        self.networkPublicKey = networkPublicKey
        self.profilePublicKeys = profilePublicKeys
    }

    enum CodingKeys: String, CodingKey {
        case path
        case correlationId = "correlation_id"
        case payload
        case destPeerId = "dest_peer_id"
        case networkPublicKey = "network_public_key"
        case profilePublicKeys = "profile_public_keys"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode fields in the exact order that Rust expects:
        // 1. path
        try container.encode(path, forKey: .path)
        // 2. correlation_id
        try container.encode(correlationId, forKey: .correlationId)
        // 3. payload (as Data byte string)
        try container.encode(payload, forKey: .payload)
        // 4. dest_peer_id
        try container.encode(destPeerId, forKey: .destPeerId)
        // 5. network_public_key (as Data if present, or null if nil)
        if let networkKey = networkPublicKey {
            try container.encode(networkKey, forKey: .networkPublicKey)
        } else {
            try container.encodeNil(forKey: .networkPublicKey)
        }
        // 6. profile_public_keys (as array of Data byte strings)
        try container.encode(profilePublicKeys, forKey: .profilePublicKeys)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        correlationId = try container.decode(String.self, forKey: .correlationId)

        // Decode payload as Data (Rust serde_bytes encodes Vec<u8> as CBOR byte string)
        payload = try container.decode(Data.self, forKey: .payload)

        destPeerId = try container.decode(String.self, forKey: .destPeerId)

        // Decode networkPublicKey as optional Data
        networkPublicKey = try container.decodeIfPresent(Data.self, forKey: .networkPublicKey)

        // Decode profilePublicKeys as array of Data (now using serde_bytes in Rust)
        profilePublicKeys = try container.decode([Data].self, forKey: .profilePublicKeys)
    }
}

/// Swift representation of TransportCompleteRequestParams from Rust FFI
/// Matches Rust struct exactly: Vec<u8> becomes Data with flexible CBOR encoding
public struct TransportCompleteRequestParams: Codable, Equatable {
    public let requestId: String
    public let responsePayload: Data // Vec<u8> in Rust
    public let profilePublicKeys: [Data] // Vec<Vec<u8>> in Rust

    public init(requestId: String, responsePayload: Data, profilePublicKeys: [Data] = []) {
        self.requestId = requestId
        self.responsePayload = responsePayload
        self.profilePublicKeys = profilePublicKeys
    }

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case responsePayload = "response_payload"
        case profilePublicKeys = "profile_public_keys"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestId, forKey: .requestId)

        // Encode as Data (byte string) to match Rust serde_bytes serialization
        try container.encode(responsePayload, forKey: .responsePayload)

        // Encode profilePublicKeys as array of Data (byte strings)
        try container.encode(profilePublicKeys, forKey: .profilePublicKeys)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try container.decode(String.self, forKey: .requestId)

        // Decode responsePayload as Data (Rust serde_bytes encodes Vec<u8> as CBOR byte string)
        responsePayload = try container.decode(Data.self, forKey: .responsePayload)

        // Decode profilePublicKeys as array of Data (now using serde_bytes in Rust)
        profilePublicKeys = try container.decode([Data].self, forKey: .profilePublicKeys)
    }
}

/// Swift representation of PeerInfo from Rust
public struct PeerInfo: Codable, Equatable, Sendable {
    public let publicKey: Data // Vec<u8> in Rust - encoded as array of bytes
    public let addresses: [String]

    public init(publicKey: Data, addresses: [String]) {
        self.publicKey = publicKey
        self.addresses = addresses
    }

    enum CodingKeys: String, CodingKey {
        case publicKey = "public_key"
        case addresses
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Encode as Data (byte string) to match Rust serde_bytes serialization
        try container.encode(publicKey, forKey: .publicKey)
        try container.encode(addresses, forKey: .addresses)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode publicKey as Data (Rust serde_bytes encodes Vec<u8> as CBOR byte string)
        publicKey = try container.decode(Data.self, forKey: .publicKey)
        addresses = try container.decode([String].self, forKey: .addresses)
    }

    /// Decode Vec<Vec<u8>> field from Rust CBOR format (array of unsignedInt arrays)
    private static func decodeVecVecU8(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> [Data] {
        // Rust serde_cbor encodes Vec<Vec<u8>> as array of arrays of unsignedInt
        let intArrays = try container.decode([[Int]].self, forKey: key)
        return intArrays.map { intArray in
            Data(intArray.map { UInt8($0) })
        }
    }
}

/// Transport publish parameters matching Rust side publish payload
public struct TransportPublishParams: Codable, Equatable {
    public let path: String
    public let correlationId: String
    public let payload: Data // Vec<u8> in Rust
    public let destPeerId: String
    public let networkPublicKey: Data? // Optional Vec<u8> in Rust

    public init(path: String, correlationId: String, payload: Data, destPeerId: String, networkPublicKey: Data? = nil) {
        self.path = path
        self.correlationId = correlationId
        self.payload = payload
        self.destPeerId = destPeerId
        self.networkPublicKey = networkPublicKey
    }

    enum CodingKeys: String, CodingKey {
        case path
        case correlationId = "correlation_id"
        case payload
        case destPeerId = "dest_peer_id"
        case networkPublicKey = "network_public_key"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(correlationId, forKey: .correlationId)

        // Encode as array of bytes to match Rust Vec<u8> serialization
        try container.encode([UInt8](payload), forKey: .payload)
        try container.encode(destPeerId, forKey: .destPeerId)

        // Encode networkPublicKey as array of bytes if present
        if let networkKey = networkPublicKey {
            try container.encode([UInt8](networkKey), forKey: .networkPublicKey)
        } else {
            try container.encodeNil(forKey: .networkPublicKey)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        correlationId = try container.decode(String.self, forKey: .correlationId)

        // Support both CBOR byte string and array<u8> for payload
        if let payloadBytes = try? container.decode([UInt8].self, forKey: .payload) {
            payload = Data(payloadBytes)
        } else {
            payload = try container.decode(Data.self, forKey: .payload)
        }

        destPeerId = try container.decode(String.self, forKey: .destPeerId)

        // Support both CBOR byte string and array<u8> for networkPublicKey
        if let networkKeyBytes = try? container.decode([UInt8].self, forKey: .networkPublicKey) {
            networkPublicKey = Data(networkKeyBytes)
        } else if try container.decodeNil(forKey: .networkPublicKey) {
            networkPublicKey = nil
        } else {
            networkPublicKey = try container.decode(Data.self, forKey: .networkPublicKey)
        }
    }
}

// MARK: - Discovery Options

/// Swift representation of DiscoveryOptions from Rust FFI
/// Matches the Rust struct in runar-transporter/src/discovery/mod.rs
public struct DiscoveryOptions: Codable, Sendable {
    /// How often to announce this node's presence (in seconds)
    public let announceInterval: TimeInterval
    /// Timeout for discovery operations (in seconds)
    public let discoveryTimeout: TimeInterval
    /// Per-peer debounce window to coalesce bursty events (in seconds)
    public let debounceWindow: TimeInterval
    /// Whether to use multicast for discovery (if supported)
    public let useMulticast: Bool
    /// Whether to limit discovery to the local network
    public let localNetworkOnly: Bool
    /// The multicast group address (e.g., "239.255.42.98")
    public let multicastGroup: String

    public init(announceInterval: TimeInterval = 1.0,
                discoveryTimeout: TimeInterval = 5.0,
                debounceWindow: TimeInterval = 0.2,
                useMulticast: Bool = true,
                localNetworkOnly: Bool = true,
                multicastGroup: String = "239.255.42.98")
    {
        self.announceInterval = announceInterval
        self.discoveryTimeout = discoveryTimeout
        self.debounceWindow = debounceWindow
        self.useMulticast = useMulticast
        self.localNetworkOnly = localNetworkOnly
        self.multicastGroup = multicastGroup
    }

    private enum CodingKeys: String, CodingKey {
        case announceInterval = "announce_interval"
        case discoveryTimeout = "discovery_timeout"
        case debounceWindow = "debounce_window"
        case useMulticast = "use_multicast"
        case localNetworkOnly = "local_network_only"
        case multicastGroup = "multicast_group"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle Duration fields that come from Rust as {secs: u64, nanos: u32}
        announceInterval = try Self.decodeDuration(from: container, forKey: .announceInterval)
        discoveryTimeout = try Self.decodeDuration(from: container, forKey: .discoveryTimeout)
        debounceWindow = try Self.decodeDuration(from: container, forKey: .debounceWindow)

        useMulticast = try container.decode(Bool.self, forKey: .useMulticast)
        localNetworkOnly = try container.decode(Bool.self, forKey: .localNetworkOnly)
        multicastGroup = try container.decode(String.self, forKey: .multicastGroup)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode Duration fields as {secs: u64, nanos: u32} to match Rust
        try Self.encodeDuration(announceInterval, to: &container, forKey: .announceInterval)
        try Self.encodeDuration(discoveryTimeout, to: &container, forKey: .discoveryTimeout)
        try Self.encodeDuration(debounceWindow, to: &container, forKey: .debounceWindow)

        try container.encode(useMulticast, forKey: .useMulticast)
        try container.encode(localNetworkOnly, forKey: .localNetworkOnly)
        try container.encode(multicastGroup, forKey: .multicastGroup)
    }

    // MARK: - Duration Helpers

    private static func decodeDuration(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> TimeInterval {
        // Try to decode as simple TimeInterval first (for Swift-generated data)
        if let timeInterval = try? container.decode(TimeInterval.self, forKey: key) {
            return timeInterval
        }

        // Try to decode as Rust Duration struct {secs: u64, nanos: u32}
        let durationContainer = try container.nestedContainer(keyedBy: DurationCodingKeys.self, forKey: key)
        let secs = try durationContainer.decode(UInt64.self, forKey: .secs)
        let nanos = try durationContainer.decode(UInt32.self, forKey: .nanos)

        return TimeInterval(secs) + TimeInterval(nanos) / 1_000_000_000.0
    }

    private static func encodeDuration(_ timeInterval: TimeInterval, to container: inout KeyedEncodingContainer<CodingKeys>, forKey key: CodingKeys) throws {
        // Encode as Rust Duration struct {secs: u64, nanos: u32}
        var durationContainer = container.nestedContainer(keyedBy: DurationCodingKeys.self, forKey: key)
        let secs = UInt64(timeInterval)
        let nanos = UInt32((timeInterval - TimeInterval(secs)) * 1_000_000_000.0)
        try durationContainer.encode(secs, forKey: .secs)
        try durationContainer.encode(nanos, forKey: .nanos)
    }

    private enum DurationCodingKeys: String, CodingKey {
        case secs
        case nanos
    }
}

// MARK: - Typed Transport Events (Swift counterparts of Rust structs)

public struct PeerConnectedEvent: Codable, Sendable, Equatable {
    public let nodeId: String
    public let nodeInfo: NodeInfo

    public init(nodeId: String, nodeInfo: NodeInfo) {
        self.nodeId = nodeId
        self.nodeInfo = nodeInfo
    }

    private enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case nodeInfo = "node_info"
    }
}

public struct TransportRequestEvent: Codable, Sendable, Equatable {
    public let requestId: String
    public let sourcePeerId: String
    public let destinationPeerId: String
    public let path: String
    public let correlationId: String
    public let payload: Data
    public let profilePublicKey: Data

    public init(requestId: String, sourcePeerId: String, destinationPeerId: String, path: String, correlationId: String, payload: Data, profilePublicKey: Data) {
        self.requestId = requestId
        self.sourcePeerId = sourcePeerId
        self.destinationPeerId = destinationPeerId
        self.path = path
        self.correlationId = correlationId
        self.payload = payload
        self.profilePublicKey = profilePublicKey
    }

    private enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case sourcePeerId = "source_peer_id"
        case destinationPeerId = "destination_peer_id"
        case path
        case correlationId = "correlation_id"
        case payload
        case profilePublicKey = "profile_public_key"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try container.decode(String.self, forKey: .requestId)
        sourcePeerId = try container.decode(String.self, forKey: .sourcePeerId)
        destinationPeerId = try container.decode(String.self, forKey: .destinationPeerId)
        path = try container.decode(String.self, forKey: .path)
        correlationId = try container.decode(String.self, forKey: .correlationId)
        if let data = try? container.decode(Data.self, forKey: .payload) {
            payload = data
        } else {
            let bytes = try container.decode([UInt8].self, forKey: .payload)
            payload = Data(bytes)
        }
        if let data = try? container.decode(Data.self, forKey: .profilePublicKey) {
            profilePublicKey = data
        } else {
            let bytes = try container.decode([UInt8].self, forKey: .profilePublicKey)
            profilePublicKey = Data(bytes)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(sourcePeerId, forKey: .sourcePeerId)
        try container.encode(destinationPeerId, forKey: .destinationPeerId)
        try container.encode(path, forKey: .path)
        try container.encode(correlationId, forKey: .correlationId)
        try container.encode([UInt8](payload), forKey: .payload)
        try container.encode([UInt8](profilePublicKey), forKey: .profilePublicKey)
    }
}

public struct TransportEventEvent: Codable, Sendable, Equatable {
    public let sourcePeerId: String
    public let destinationPeerId: String
    public let path: String
    public let correlationId: String
    public let payload: Data

    public init(sourcePeerId: String, destinationPeerId: String, path: String, correlationId: String, payload: Data) {
        self.sourcePeerId = sourcePeerId
        self.destinationPeerId = destinationPeerId
        self.path = path
        self.correlationId = correlationId
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePeerId = "source_peer_id"
        case destinationPeerId = "destination_peer_id"
        case path
        case correlationId = "correlation_id"
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePeerId = try container.decode(String.self, forKey: .sourcePeerId)
        destinationPeerId = try container.decode(String.self, forKey: .destinationPeerId)
        path = try container.decode(String.self, forKey: .path)
        correlationId = try container.decode(String.self, forKey: .correlationId)
        if let data = try? container.decode(Data.self, forKey: .payload) {
            payload = data
        } else {
            let bytes = try container.decode([UInt8].self, forKey: .payload)
            payload = Data(bytes)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourcePeerId, forKey: .sourcePeerId)
        try container.encode(destinationPeerId, forKey: .destinationPeerId)
        try container.encode(path, forKey: .path)
        try container.encode(correlationId, forKey: .correlationId)
        try container.encode([UInt8](payload), forKey: .payload)
    }
}

public struct TransportResponseEvent: Codable, Sendable, Equatable {
    public let correlationId: String
    public let payload: Data

    public init(correlationId: String, payload: Data) {
        self.correlationId = correlationId
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case correlationId = "correlation_id"
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        correlationId = try container.decode(String.self, forKey: .correlationId)
        if let data = try? container.decode(Data.self, forKey: .payload) {
            payload = data
        } else {
            let bytes = try container.decode([UInt8].self, forKey: .payload)
            payload = Data(bytes)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(correlationId, forKey: .correlationId)
        try container.encode([UInt8](payload), forKey: .payload)
    }
}
