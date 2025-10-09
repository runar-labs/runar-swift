import Foundation
import SwiftCBOR
import SwiftCommon
@testable import SwiftFFI
import XCTest

/// FFI Types Vector Generator - Single file to generate ALL test vectors
/// This file generates CBOR test vectors for all 37 types defined in SwiftFFI+Schema.swift
/// Run this to generate all bin files needed for cross-platform validation
final class FFITypesVectorGenerator: XCTestCase {
    let outputDir = URL(fileURLWithPath: "target/ffi-types-vectors-swift")

    override func setUp() {
        super.setUp()
        // Create output directory if it doesn't exist
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    func testGenerateAllFFITypesVectors() throws {
        print("🔬 Generating ALL FFI Types Test Vectors")
        print("======================================")
        print("Generating vectors for all 37 types from SwiftFFI+Schema.swift (includes Swift-only types)")

        // CA Client Types (9 types)
        try generateEnrollmentTokenBody()
        try generateEnrollmentToken()
        try generateSetupToken()
        try generateCsrEnrollRequest()
        try generateCsrEnrollResponse()
        try generateRenewRequest()
        try generateRenewResponse()
        try generateRevokeRequest()
        try generateRevokeResponse()

        // CA Configuration Types (6 types)
        try generateCaStatus()
        try generateChainResponse()
        try generateCaErrorResponse()
        try generateCaServerConfig()
        try generateCaClientConfigAll()
        try generateCustomCaServerConfig()

        // Network Message Types (2 types)
        try generateNetworkMessagePayloadItem()
        try generateNetworkMessage()

        // Handshake Types (2 types)
        try generateConnectionRole()
        try generateHandshakeData()

        // Node Info Types (6 types)
        try generateNodeInfo()
        try generateNodeMetadata()
        try generateServiceMetadata()
        try generateActionMetadata()
        try generateSubscriptionMetadata()
        try generateFieldSchema()
        try generateSchemaDataType()

        // Transport Types (4 types)
        try generatePeerInfo()
        try generateTransportRequestParams()
        try generateTransportCompleteRequestParams()
        try generateTransportPublishParams()

        // Transport Options (2 types)
        try generateFFIQuicTransportOptions()
        try generateQuicTransportOptions()

        // Discovery Types (1 type)
        try generateDiscoveryOptions()

        // Transport Event Types (4 types)
        try generateTypedTransportEventVectors()

        print("✅ All 38 FFI types test vectors generated successfully")
        print("📁 Output directory: \(outputDir.path)")
    }

    // MARK: - CA Client Types Generation

    private func generateEnrollmentTokenBody() throws {
        let tokenBody = EnrollmentTokenBody(
            token_id: "test_token_001",
            network_id: "test_network",
            subject_hint: "test_subject",
            not_before: 1_757_890_822,
            expires_at: 1_757_894_422,
            nonce: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
            permissions: ["enroll"]
        )
        try encodeAndWrite(tokenBody, filename: "enrollment_token_body_basic.bin")
    }

    private func generateEnrollmentToken() throws {
        let tokenBody = EnrollmentTokenBody(
            token_id: "test_token_001",
            network_id: "test_network",
            subject_hint: "test_subject",
            not_before: 1_757_890_822,
            expires_at: 1_757_894_422,
            nonce: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
            permissions: ["enroll"]
        )
        let enrollmentToken = EnrollmentToken(
            body: tokenBody,
            signature: Data(Array(repeating: 1, count: 70)),
            signer_id: "test_signer_001"
        )
        try encodeAndWrite(enrollmentToken, filename: "enrollment_token_basic.bin")
    }

    private func generateSetupToken() throws {
        let setupToken = SetupToken(
            node_id: "test_node_001",
            node_public_key: Array(repeating: 1, count: 65),
            node_agreement_public_key: Array(repeating: 2, count: 65),
            csr_der: Array(repeating: 3, count: 318)
        )
        try encodeAndWrite(setupToken, filename: "setup_token_basic.bin")
    }

    private func generateCsrEnrollRequest() throws {
        let tokenBody = EnrollmentTokenBody(
            token_id: "test_token_001",
            network_id: "test_network",
            subject_hint: "test_subject",
            not_before: 1_757_890_822,
            expires_at: 1_757_894_422,
            nonce: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
            permissions: ["enroll"]
        )
        let enrollmentToken = EnrollmentToken(
            body: tokenBody,
            signature: Data(Array(repeating: 1, count: 70)),
            signer_id: "test_signer_001"
        )
        let csrEnrollRequest = CsrEnrollRequest(
            network_id: "test_network",
            csr_der: Data(Array(repeating: 7, count: 318)),
            enrollment_token: enrollmentToken
        )
        try encodeAndWrite(csrEnrollRequest, filename: "csr_enroll_request_basic.bin")
    }

    private func generateCsrEnrollResponse() throws {
        let csrEnrollResponse = CsrEnrollResponse(
            network_id: "test_network",
            certificate_der: Data(Array(repeating: 9, count: 1024)),
            issuing_ca_der: Data(Array(repeating: 10, count: 512)),
            root_ca_der: Data(Array(repeating: 11, count: 256)),
            expires_at: 1_757_894_422
        )
        try encodeAndWrite(csrEnrollResponse, filename: "csr_enroll_response_basic.bin")
    }

    private func generateRenewRequest() throws {
        let renewRequest = RenewRequest(
            network_id: "test_network",
            csr_der: Data(Array(repeating: 1, count: 318))
        )
        try encodeAndWrite(renewRequest, filename: "renew_request_basic.bin")
    }

    private func generateRenewResponse() throws {
        let renewResponse = RenewResponse(
            network_id: "test_network",
            certificate_der: Data(Array(repeating: 3, count: 1024)),
            issuing_ca_der: Data(Array(repeating: 4, count: 512)),
            expires_at: 1_757_894_422
        )
        try encodeAndWrite(renewResponse, filename: "renew_response_basic.bin")
    }

    private func generateRevokeRequest() throws {
        let revokeRequest = RevokeRequest(
            network_id: "test_network",
            certificate_serial: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]),
            reason: "testing"
        )
        try encodeAndWrite(revokeRequest, filename: "revoke_request_basic.bin")
    }

    private func generateRevokeResponse() throws {
        let revokeResponse = RevokeResponse(
            network_id: "test_network",
            ok: true
        )
        try encodeAndWrite(revokeResponse, filename: "revoke_response_basic.bin")
    }

    // MARK: - CA Configuration Types Generation

    private func generateCaStatus() throws {
        let caStatus = CaStatus(
            network_id: "test_network",
            issuing_subject: "CN=Test Issuing CA,O=Test,C=US",
            issuing_serial_hex: "1234567890ABCDEF",
            not_before: 1_757_890_822,
            not_after: 1_757_894_422
        )
        try encodeAndWrite(caStatus, filename: "ca_status_basic.bin")
    }

    private func generateChainResponse() throws {
        let chainResponse = ChainResponse(
            network_id: "test_network",
            issuing_ca_der: Data(Array(repeating: 1, count: 512)),
            root_ca_der: Data(Array(repeating: 2, count: 256))
        )
        try encodeAndWrite(chainResponse, filename: "chain_response_basic.bin")
    }

    private func generateCaErrorResponse() throws {
        let caErrorResponse = CaErrorResponse(
            code: "unauthorized",
            message: "Invalid enrollment token",
            reason: nil
        )
        try encodeAndWrite(caErrorResponse, filename: "ca_error_response_basic.bin")
    }

    private func generateCaServerConfig() throws {
        let caServerConfig = CaServerConfig(
            bootstrapBind: "0.0.0.0:8080",
            authenticatedBind: "0.0.0.0:8081",
            networkId: "test_network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        try encodeAndWrite(caServerConfig, filename: "ca_server_config_basic.bin")
    }

    private func generateCaClientConfigAll() throws {
        let caClientConfig = try CaClientConfigAll(
            bootstrap_server: "127.0.0.1:8443",
            authenticated_server: "127.0.0.1:8444",
            network_id: "test_network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Array(repeating: 1, count: 256),
            issuing_ca_der: Array(repeating: 2, count: 512)
        )
        try encodeAndWrite(caClientConfig, filename: "ca_client_config_all_basic.bin")
    }

    private func generateCustomCaServerConfig() throws {
        let customCaServerConfig = CustomCaServerConfig(
            bootstrap_bind: "127.0.0.1:8443",
            authenticated_bind: "127.0.0.1:8444",
            network_id: "test_network",
            rate_limit_per_minute: 100,
            rate_limit_per_hour: 1000
        )
        try encodeAndWrite(customCaServerConfig, filename: "custom_ca_server_config_basic.bin")
    }

    // MARK: - Network Message Types Generation

    private func generateNetworkMessagePayloadItem() throws {
        let payload = NetworkMessagePayloadItem(
            path: "/api/test",
            payloadBytes: Data("test payload data".utf8),
            correlationId: "corr_123",
            networkPublicKey: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
            profilePublicKeys: [
                Data([11, 12, 13, 14, 15]),
                Data([16, 17, 18, 19, 20]),
            ]
        )
        try encodeAndWrite(payload, filename: "network_message_payload_item_basic.bin")
    }

    private func generateNetworkMessage() throws {
        let payload = NetworkMessagePayloadItem(
            path: "/api/request",
            payloadBytes: Data("request data".utf8),
            correlationId: "req_123",
            networkPublicKey: Data([1, 2, 3, 4, 5]),
            profilePublicKeys: [Data([6, 7, 8, 9, 10])]
        )
        let message = NetworkMessage(
            sourceNodeId: "node_123",
            destinationNodeId: "node_456",
            messageType: 4, // MESSAGE_TYPE_REQUEST
            payload: payload
        )
        try encodeAndWrite(message, filename: "network_message_basic.bin")
    }

    // MARK: - Handshake Types Generation

    private func generateConnectionRole() throws {
        // Test both enum values
        let initiator = ConnectionRole.initiator
        let responder = ConnectionRole.responder
        try encodeAndWrite(initiator, filename: "connection_role_initiator.bin")
        try encodeAndWrite(responder, filename: "connection_role_responder.bin")
    }

    private func generateHandshakeData() throws {
        let basicNode = NodeInfo(
            nodePublicKey: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]),
            networkIds: ["test-network"],
            addresses: ["127.0.0.1:8080"],
            nodeMetadata: NodeMetadata(services: [], subscriptions: []),
            version: 1
        )
        let handshakeData = HandshakeData(
            nodeInfo: basicNode,
            nonce: 1_234_567_890,
            role: .initiator
        )
        try encodeAndWrite(handshakeData, filename: "handshake_data_basic.bin")
    }

    // MARK: - Node Info Types Generation

    private func generateNodeInfo() throws {
        // Basic node info
        let basicNode = NodeInfo(
            nodePublicKey: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]),
            networkIds: ["test-network"],
            addresses: ["127.0.0.1:8080"],
            nodeMetadata: NodeMetadata(services: [], subscriptions: []),
            version: 1
        )
        try encodeAndWrite(basicNode, filename: "node_info_basic.bin")

        // Node info with metadata
        let nodeWithMetadata = NodeInfo(
            nodePublicKey: Data([32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]),
            networkIds: ["test-network", "another-network"],
            addresses: ["127.0.0.1:8080", "192.168.1.100:8080"],
            nodeMetadata: NodeMetadata(
                services: [
                    ServiceMetadata(
                        networkId: "test-network",
                        servicePath: "/api/test",
                        name: "test-service",
                        version: "1.0.0",
                        description: "A test service",
                        actions: [],
                        registrationTime: 1_234_567_890,
                        lastStartTime: 1_234_567_891
                    ),
                ],
                subscriptions: [
                    SubscriptionMetadata(path: "test-topic"),
                ]
            ),
            version: 2
        )
        try encodeAndWrite(nodeWithMetadata, filename: "node_info_with_metadata.bin")
    }

    private func generateNodeMetadata() throws {
        let nodeMetadata = NodeMetadata(
            services: [],
            subscriptions: []
        )
        try encodeAndWrite(nodeMetadata, filename: "node_metadata_basic.bin")
    }

    private func generateServiceMetadata() throws {
        let serviceMetadata = ServiceMetadata(
            networkId: "test_network",
            servicePath: "/test_service",
            name: "test_service",
            version: "1.0.0",
            description: "Test service description",
            actions: [],
            registrationTime: 1_678_886_400,
            lastStartTime: 1_678_886_400
        )
        try encodeAndWrite(serviceMetadata, filename: "service_metadata_basic.bin")
    }

    private func generateActionMetadata() throws {
        let actionMetadata = ActionMetadata(
            name: "test_action",
            description: "Test action description",
            inputSchema: nil,
            outputSchema: nil
        )
        try encodeAndWrite(actionMetadata, filename: "action_metadata_basic.bin")
    }

    private func generateSubscriptionMetadata() throws {
        let subscriptionMetadata = SubscriptionMetadata(path: "/test_topic")
        try encodeAndWrite(subscriptionMetadata, filename: "subscription_metadata_basic.bin")
    }

    private func generateFieldSchema() throws {
        let fieldSchema = FieldSchema(
            dataType: .string,
            required: true,
            description: "A test field"
        )
        try encodeAndWrite(fieldSchema, filename: "field_schema_basic.bin")
    }

    private func generateSchemaDataType() throws {
        // Test all enum values
        let stringType = SchemaDataType.string
        let int32Type = SchemaDataType.int32
        let int64Type = SchemaDataType.int64
        let float32Type = SchemaDataType.float32
        let float64Type = SchemaDataType.float64
        let booleanType = SchemaDataType.boolean
        let bytesType = SchemaDataType.bytes
        let arrayType = SchemaDataType.array
        let mapType = SchemaDataType.map

        try encodeAndWrite(stringType, filename: "schema_data_type_string.bin")
        try encodeAndWrite(int32Type, filename: "schema_data_type_int32.bin")
        try encodeAndWrite(int64Type, filename: "schema_data_type_int64.bin")
        try encodeAndWrite(float32Type, filename: "schema_data_type_float32.bin")
        try encodeAndWrite(float64Type, filename: "schema_data_type_float64.bin")
        try encodeAndWrite(booleanType, filename: "schema_data_type_boolean.bin")
        try encodeAndWrite(bytesType, filename: "schema_data_type_bytes.bin")
        try encodeAndWrite(arrayType, filename: "schema_data_type_array.bin")
        try encodeAndWrite(mapType, filename: "schema_data_type_map.bin")
    }

    // MARK: - Transport Types Generation

    private func generatePeerInfo() throws {
        let peerInfo = PeerInfo(
            publicKey: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]),
            addresses: ["127.0.0.1:8080", "192.168.1.100:9090"]
        )
        try encodeAndWrite(peerInfo, filename: "peer_info_basic.bin")
    }

    private func generateTransportRequestParams() throws {
        let params = TransportRequestParams(
            path: "/api/test",
            correlationId: "corr_789",
            payload: Data("test payload".utf8),
            destPeerId: "peer_123",
            networkPublicKey: Data([1, 2, 3, 4, 5]),
            profilePublicKeys: [Data([6, 7, 8, 9, 10]), Data([11, 12, 13, 14, 15])]
        )
        try encodeAndWrite(params, filename: "transport_request_params_basic.bin")
    }

    private func generateTransportCompleteRequestParams() throws {
        let params = TransportCompleteRequestParams(
            requestId: "req_456",
            responsePayload: Data("response data".utf8),
            profilePublicKeys: [Data([1, 2, 3]), Data([4, 5, 6])]
        )
        try encodeAndWrite(params, filename: "transport_complete_request_params_basic.bin")
    }

    private func generateTransportPublishParams() throws {
        let params = TransportPublishParams(
            path: "/publish/test",
            correlationId: "pub_123",
            payload: Data("publish data".utf8),
            destPeerId: "peer_789",
            networkPublicKey: Data([1, 2, 3, 4, 5])
        )
        try encodeAndWrite(params, filename: "transport_publish_params_basic.bin")
    }

    // MARK: - Transport Options Generation

    private func generateFFIQuicTransportOptions() throws {
        let options = FFIQuicTransportOptions(
            bindAddr: "0.0.0.0:8080",
            handshakeTimeoutMs: 5000,
            openStreamTimeoutMs: 1000,
            maxMessageSize: 1024 * 1024,
            responseCacheTtlMs: 30000,
            maxRequestRetries: 3,
            certChainDer: [
                Data([0x30, 0x82, 0x01, 0x22]), // Sample DER data
                Data([0x30, 0x82, 0x01, 0x33]),
            ],
            privateKeyDer: Data([0x30, 0x82, 0x01, 0x44]), // Sample DER data
            rootCertsDer: [
                Data([0x30, 0x82, 0x01, 0x55]), // Sample DER data
                Data([0x30, 0x82, 0x01, 0x66]),
            ]
        )
        try encodeAndWrite(options, filename: "ffi_quic_transport_options_basic.bin")
    }

    private func generateQuicTransportOptions() throws {
        let options = QuicTransportOptions(
            requestTimeoutSeconds: 30,
            bindAddr: "0.0.0.0:8080",
            handshakeTimeoutMs: 5000,
            openStreamTimeoutMs: 1000,
            maxMessageSize: 1024 * 1024,
            responseCacheTtlMs: 30000,
            maxRequestRetries: 3,
            certChainDer: [
                Data([0x30, 0x82, 0x01, 0x22]), // Sample DER data
                Data([0x30, 0x82, 0x01, 0x33]),
            ],
            privateKeyDer: Data([0x30, 0x82, 0x01, 0x44]), // Sample DER data
            rootCertsDer: [
                Data([0x30, 0x82, 0x01, 0x55]), // Sample DER data
                Data([0x30, 0x82, 0x01, 0x66]),
            ]
        )
        try encodeAndWrite(options, filename: "quic_transport_options_basic.bin")
    }

    // MARK: - Discovery Types Generation

    private func generateDiscoveryOptions() throws {
        let options = DiscoveryOptions(
            announceInterval: 1.0,
            discoveryTimeout: 5.0,
            debounceWindow: 0.2,
            useMulticast: true,
            localNetworkOnly: true,
            multicastGroup: "239.255.42.98"
        )
        try encodeAndWrite(options, filename: "discovery_options_basic.bin")
    }

    // MARK: - Transport Event Types Generation

    private func generateTypedTransportEventVectors() throws {
        // Basic NodeInfo fixture
        let basicNode = NodeInfo(
            nodePublicKey: Data([1, 2, 3, 4, 5]),
            networkIds: ["net-a"],
            addresses: ["127.0.0.1:0"],
            nodeMetadata: NodeMetadata(services: [], subscriptions: []),
            version: 1
        )

        // PeerConnectedEvent
        let peerConnected = PeerConnectedEvent(
            nodeId: "node-123",
            nodeInfo: basicNode
        )
        try encodeAndWrite(peerConnected, filename: "peer_connected_event_basic.bin")

        // TransportRequestEvent
        let transportRequest = TransportRequestEvent(
            requestId: "req-1",
            sourcePeerId: "source-peer-123",
            destinationPeerId: "dest-peer-456",
            path: "/echo",
            correlationId: "c1",
            payload: Data("hello".utf8),
            profilePublicKey: Data()
        )
        try encodeAndWrite(transportRequest, filename: "transport_request_event_basic.bin")

        // TransportEventEvent
        let transportEvent = TransportEventEvent(
            sourcePeerId: "source-peer-789",
            destinationPeerId: "dest-peer-012",
            path: "/event",
            correlationId: "e1",
            payload: Data("evt".utf8)
        )
        try encodeAndWrite(transportEvent, filename: "transport_event_event_basic.bin")

        // TransportResponseEvent
        let transportResponse = TransportResponseEvent(
            correlationId: "c1",
            payload: Data("world".utf8)
        )
        try encodeAndWrite(transportResponse, filename: "transport_response_event_basic.bin")
    }

    // MARK: - Helper Methods

    private func encodeAndWrite<T: Codable>(_ value: T, filename: String) throws {
        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(value)
        try data.write(to: outputDir.appendingPathComponent(filename))
        print("✅ Generated: \(filename)")
    }
}
