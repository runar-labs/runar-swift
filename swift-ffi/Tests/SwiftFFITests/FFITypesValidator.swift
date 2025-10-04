import Foundation
import SwiftCBOR
import SwiftCommon
@testable import SwiftFFI
import XCTest

/// FFI Types Validator - Single file to validate ALL types against Rust
/// This file validates all 37 types from SwiftFFI+Schema.swift against their Rust counterparts
/// Run this after generating vectors on both Swift and Rust sides
final class FFITypesValidator: XCTestCase {
    let swiftDir = URL(fileURLWithPath: "target/ffi-types-vectors-swift")
    let rustDir = URL(fileURLWithPath: "../../runar-rust/rust-examples/target/ffi-types-vectors")

    func testValidateAllFFITypesAgainstRust() async throws {
        print("🔬 Validating ALL FFI Types Against Rust")
        print("======================================")
        print("Validating all 36 FFI types from SwiftFFI+Schema.swift against Rust counterparts")

        guard FileManager.default.fileExists(atPath: swiftDir.path) else {
            XCTFail("Swift FFI types vectors directory not found: \(swiftDir.path). Run Swift FFI types vectors first.")
            return
        }

        guard FileManager.default.fileExists(atPath: rustDir.path) else {
            XCTFail("Rust FFI types vectors directory not found: \(rustDir.path). Run Rust FFI types vectors first.")
            return
        }

        print("📁 Found FFI types vector directories:")
        print("   Swift: \(swiftDir.path)")
        print("   Rust:  \(rustDir.path)")

        // Define all 36 FFI types with their validation functions (excludes Swift-only types)
        let typeValidations = [
            // CA Client Types (9 types)
            ("EnrollmentTokenBody", validateEnrollmentTokenBody),
            ("EnrollmentToken", validateEnrollmentToken),
            ("SetupToken", validateSetupToken),
            ("CsrEnrollRequest", validateCsrEnrollRequest),
            ("CsrEnrollResponse", validateCsrEnrollResponse),
            ("RenewRequest", validateRenewRequest),
            ("RenewResponse", validateRenewResponse),
            ("RevokeRequest", validateRevokeRequest),
            ("RevokeResponse", validateRevokeResponse),

            // CA Configuration Types (6 types)
            ("CaStatus", validateCaStatus),
            ("ChainResponse", validateChainResponse),
            ("CaErrorResponse", validateCaErrorResponse),
            ("CaServerConfig", validateCaServerConfig),
            ("CaClientConfigAll", validateCaClientConfigAll),
            ("CustomCaServerConfig", validateCustomCaServerConfig),

            // Network Message Types (2 types)
            ("NetworkMessagePayloadItem", validateNetworkMessagePayloadItem),
            ("NetworkMessage", validateNetworkMessage),

            // Handshake Types (2 types)
            ("ConnectionRole", validateConnectionRole),
            ("HandshakeData", validateHandshakeData),

            // Node Info Types (6 types)
            ("NodeInfo", validateNodeInfo),
            ("NodeMetadata", validateNodeMetadata),
            ("ServiceMetadata", validateServiceMetadata),
            ("ActionMetadata", validateActionMetadata),
            ("SubscriptionMetadata", validateSubscriptionMetadata),
            ("FieldSchema", validateFieldSchema),
            ("SchemaDataType", validateSchemaDataType),

            // Transport Types (4 types)
            ("PeerInfo", validatePeerInfo),
            ("TransportRequestParams", validateTransportRequestParams),
            ("TransportCompleteRequestParams", validateTransportCompleteRequestParams),
            ("TransportPublishParams", validateTransportPublishParams),

            // Transport Options (1 type)
            ("FFIQuicTransportOptions", validateFFIQuicTransportOptions),

            // Discovery Types (1 type)
            ("DiscoveryOptions", validateDiscoveryOptions),

            // Transport Event Types (4 types)
            ("PeerConnectedEvent", validatePeerConnectedEvent),
            ("TransportRequestEvent", validateTransportRequestEvent),
            ("TransportEventEvent", validateTransportEventEvent),
            ("TransportResponseEvent", validateTransportResponseEvent),
        ]

        var passed = 0
        var failed = 0

        for (typeName, validationFunc) in typeValidations {
            do {
                try await validationFunc()
                print("✅ \(typeName) validation passed")
                passed += 1
            } catch {
                print("❌ \(typeName) validation failed: \(error)")
                failed += 1
            }
        }

        print("\n📊 FFI Types Validation Results")
        print("================================")
        print("✅ Passed: \(passed)")
        print("❌ Failed: \(failed)")
        print("📈 Success Rate: \(String(format: "%.1f", (Double(passed) / Double(passed + failed)) * 100.0))%")

        if failed > 0 {
            XCTFail("\(failed) FFI types validations failed")
        } else {
            print("\n🎉 All 36 FFI types validations passed! Swift and Rust CBOR are 100% compatible!")
        }
    }

    // MARK: - Validation Methods

    private func validateEnrollmentTokenBody() async throws {
        try await validateType(EnrollmentTokenBody.self, filename: "enrollment_token_body_basic.bin")
    }

    private func validateEnrollmentToken() async throws {
        try await validateType(EnrollmentToken.self, filename: "enrollment_token_basic.bin")
    }

    private func validateSetupToken() async throws {
        try await validateType(SetupToken.self, filename: "setup_token_basic.bin")
    }

    private func validateCsrEnrollRequest() async throws {
        try await validateType(CsrEnrollRequest.self, filename: "csr_enroll_request_basic.bin")
    }

    private func validateCsrEnrollResponse() async throws {
        try await validateType(CsrEnrollResponse.self, filename: "csr_enroll_response_basic.bin")
    }

    private func validateRenewRequest() async throws {
        try await validateType(RenewRequest.self, filename: "renew_request_basic.bin")
    }

    private func validateRenewResponse() async throws {
        try await validateType(RenewResponse.self, filename: "renew_response_basic.bin")
    }

    private func validateRevokeRequest() async throws {
        try await validateType(RevokeRequest.self, filename: "revoke_request_basic.bin")
    }

    private func validateRevokeResponse() async throws {
        try await validateType(RevokeResponse.self, filename: "revoke_response_basic.bin")
    }

    private func validateCaStatus() async throws {
        try await validateType(CaStatus.self, filename: "ca_status_basic.bin")
    }

    private func validateChainResponse() async throws {
        try await validateType(ChainResponse.self, filename: "chain_response_basic.bin")
    }

    private func validateCaErrorResponse() async throws {
        try await validateType(CaErrorResponse.self, filename: "ca_error_response_basic.bin")
    }

    private func validateCaServerConfig() async throws {
        try await validateType(CaServerConfig.self, filename: "ca_server_config_basic.bin")
    }

    private func validateCaClientConfigAll() async throws {
        try await validateType(CaClientConfigAll.self, filename: "ca_client_config_all_basic.bin")
    }

    private func validateCustomCaServerConfig() async throws {
        try await validateType(CustomCaServerConfig.self, filename: "custom_ca_server_config_basic.bin")
    }

    private func validateNetworkMessagePayloadItem() async throws {
        try await validateType(NetworkMessagePayloadItem.self, filename: "network_message_payload_item_basic.bin")
    }

    private func validateNetworkMessage() async throws {
        try await validateType(NetworkMessage.self, filename: "network_message_basic.bin")
    }

    private func validateConnectionRole() async throws {
        try await validateType(ConnectionRole.self, filename: "connection_role_initiator.bin")
        try await validateType(ConnectionRole.self, filename: "connection_role_responder.bin")
    }

    private func validateHandshakeData() async throws {
        try await validateType(HandshakeData.self, filename: "handshake_data_basic.bin")
    }

    private func validateNodeInfo() async throws {
        try await validateType(NodeInfo.self, filename: "node_info_basic.bin")
        try await validateType(NodeInfo.self, filename: "node_info_with_metadata.bin")
    }

    private func validateNodeMetadata() async throws {
        try await validateType(NodeMetadata.self, filename: "node_metadata_basic.bin")
    }

    private func validateServiceMetadata() async throws {
        try await validateType(ServiceMetadata.self, filename: "service_metadata_basic.bin")
    }

    private func validateActionMetadata() async throws {
        try await validateType(ActionMetadata.self, filename: "action_metadata_basic.bin")
    }

    private func validateSubscriptionMetadata() async throws {
        try await validateType(SubscriptionMetadata.self, filename: "subscription_metadata_basic.bin")
    }

    private func validateFieldSchema() async throws {
        try await validateType(FieldSchema.self, filename: "field_schema_basic.bin")
    }

    private func validateSchemaDataType() async throws {
        try await validateType(SchemaDataType.self, filename: "schema_data_type_string.bin")
        try await validateType(SchemaDataType.self, filename: "schema_data_type_int32.bin")
        try await validateType(SchemaDataType.self, filename: "schema_data_type_int64.bin")
        try await validateType(SchemaDataType.self, filename: "schema_data_type_float32.bin")
        try await validateType(SchemaDataType.self, filename: "schema_data_type_float64.bin")
        try await validateType(SchemaDataType.self, filename: "schema_data_type_boolean.bin")
        try await validateType(SchemaDataType.self, filename: "schema_data_type_bytes.bin")
        try await validateType(SchemaDataType.self, filename: "schema_data_type_array.bin")
        try await validateType(SchemaDataType.self, filename: "schema_data_type_map.bin")
    }

    private func validatePeerInfo() async throws {
        try await validateType(PeerInfo.self, filename: "peer_info_basic.bin")
    }

    private func validateTransportRequestParams() async throws {
        try await validateType(TransportRequestParams.self, filename: "transport_request_params_basic.bin")
    }

    private func validateTransportCompleteRequestParams() async throws {
        try await validateType(TransportCompleteRequestParams.self, filename: "transport_complete_request_params_basic.bin")
    }

    private func validateTransportPublishParams() async throws {
        try await validateType(TransportPublishParams.self, filename: "transport_publish_params_basic.bin")
    }

    private func validateFFIQuicTransportOptions() async throws {
        try await validateType(FFIQuicTransportOptions.self, filename: "ffi_quic_transport_options_basic.bin")
    }

    private func validateQuicTransportOptions() async throws {
        try await validateTypeNonEquatable(QuicTransportOptions.self, filename: "quic_transport_options_basic.bin")
    }

    private func validateDiscoveryOptions() async throws {
        try await validateTypeNonEquatable(DiscoveryOptions.self, filename: "discovery_options_basic.bin")
    }

    private func validatePeerConnectedEvent() async throws {
        try await validateType(PeerConnectedEvent.self, filename: "peer_connected_event_basic.bin")
    }

    private func validateTransportRequestEvent() async throws {
        try await validateType(TransportRequestEvent.self, filename: "transport_request_event_basic.bin")
    }

    private func validateTransportEventEvent() async throws {
        try await validateType(TransportEventEvent.self, filename: "transport_event_event_basic.bin")
    }

    private func validateTransportResponseEvent() async throws {
        try await validateType(TransportResponseEvent.self, filename: "transport_response_event_basic.bin")
    }

    // MARK: - Helper Methods

    private func validateType<T: Codable & Equatable>(_ type: T.Type, filename: String) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent(filename))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent(filename))

        let swiftValue: T = try CodableCBORDecoder().decode(type, from: swiftData)
        let rustValue: T = try CodableCBORDecoder().decode(type, from: rustData)

        if swiftValue != rustValue {
            throw ValidationError.mismatch("\(type) validation failed - Swift and Rust data don't match")
        }
    }

    private enum ValidationError: Error {
        case mismatch(String)
    }

    private func validateTypeNonEquatable<T: Codable>(_ type: T.Type, filename: String) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent(filename))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent(filename))

        // For non-equatable types, we just verify they can be decoded successfully
        let _: T = try CodableCBORDecoder().decode(type, from: swiftData)
        let _: T = try CodableCBORDecoder().decode(type, from: rustData)

        // If we get here, both decoded successfully
        print("✅ \(type) validation passed (both decoded successfully)")
    }
}
