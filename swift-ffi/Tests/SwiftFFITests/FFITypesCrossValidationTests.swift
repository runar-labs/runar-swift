import Foundation
import SwiftCBOR
import SwiftCommon
@testable import SwiftFFI
import XCTest

final class FFITypesCrossValidationTests: XCTestCase {
    func testFFITypesCrossValidation() async throws {
        print("🔬 FFI Types CBOR Cross-Platform Validation")
        print("===========================================")

        // Check that both directories exist
        let swiftDir = URL(fileURLWithPath: "target/ffi-types-vectors-swift")
        let rustDir = URL(fileURLWithPath: "../../runar-rust/rust-examples/target/ffi-types-vectors")

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

        print("\n🚀 Running FFI types validation tests...")

        // Run all validation tests
        let tests = [
            ("EnrollmentTokenBody", validateEnrollmentTokenBody),
            ("EnrollmentToken", validateEnrollmentToken),
            ("SetupToken", validateSetupToken),
            ("CsrEnrollRequest", validateCsrEnrollRequest),
            ("CsrEnrollResponse", validateCsrEnrollResponse),
            ("RenewRequest", validateRenewRequest),
            ("RenewResponse", validateRenewResponse),
            ("RevokeRequest", validateRevokeRequest),
            ("RevokeResponse", validateRevokeResponse),
            ("CaStatus", validateCaStatus),
            ("ChainResponse", validateChainResponse),
            ("CaErrorResponse", validateCaErrorResponse),
            ("NodeInfo", validateNodeInfo),
            ("NetworkMessagePayloadItem", validateNetworkMessagePayloadItem),
            ("NetworkMessage", validateNetworkMessage),
            ("PeerConnectedEvent", validatePeerConnectedEventRustToSwift),
            ("TransportRequestEvent", validateTransportRequestEventRustToSwift),
            ("TransportEventEvent", validateTransportEventEventRustToSwift),
            ("TransportResponseEvent", validateTransportResponseEventRustToSwift),
        ]

        var passed = 0
        var failed = 0

        for (name, test) in tests {
            do {
                try await test(swiftDir, rustDir)
                print("✅ \(name) validation passed")
                passed += 1
            } catch {
                print("❌ \(name) validation failed: \(error)")
                failed += 1
            }
        }

        print("\n📊 FFI Types Validation Results")
        print("================================")
        print("✅ Passed: \(passed)")
        print("❌ Failed: \(failed)")
        print("📈 Success Rate: \(String(format: "%.1f", (Double(passed) / Double(passed + failed)) * 100.0))%")

        if failed == 0 {
            print("\n🎉 All FFI types validations passed! Swift and Rust CBOR are compatible!")
        } else {
            print("\n⚠️  Some FFI types validations failed. Check the output above for details.")
            XCTFail("\(failed) FFI types validations failed")
        }
    }

    private func validateEnrollmentTokenBody(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("enrollment_token_body_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("enrollment_token_body_basic.bin"))

        let swiftBody: EnrollmentTokenBody = try CodableCBORDecoder().decode(EnrollmentTokenBody.self, from: swiftData)
        let rustBody: EnrollmentTokenBody = try CodableCBORDecoder().decode(EnrollmentTokenBody.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftBody, rustBody, "EnrollmentTokenBody validation failed - Swift and Rust data don't match")
    }

    private func validateEnrollmentToken(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("enrollment_token_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("enrollment_token_basic.bin"))

        let swiftToken: EnrollmentToken = try CodableCBORDecoder().decode(EnrollmentToken.self, from: swiftData)
        let rustToken: EnrollmentToken = try CodableCBORDecoder().decode(EnrollmentToken.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftToken, rustToken, "EnrollmentToken validation failed - Swift and Rust data don't match")
    }

    private func validateSetupToken(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("setup_token_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("setup_token_basic.bin"))

        let swiftSetup: SetupToken = try CodableCBORDecoder().decode(SetupToken.self, from: swiftData)
        let rustSetup: SetupToken = try CodableCBORDecoder().decode(SetupToken.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftSetup, rustSetup, "SetupToken validation failed - Swift and Rust data don't match")
    }

    private func validateCsrEnrollRequest(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("csr_enroll_request_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("csr_enroll_request_basic.bin"))

        let swiftRequest: CsrEnrollRequest = try CodableCBORDecoder().decode(CsrEnrollRequest.self, from: swiftData)
        let rustRequest: CsrEnrollRequest = try CodableCBORDecoder().decode(CsrEnrollRequest.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftRequest, rustRequest, "CsrEnrollRequest validation failed - Swift and Rust data don't match")
    }

    private func validateCsrEnrollResponse(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("csr_enroll_response_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("csr_enroll_response_basic.bin"))

        let swiftResponse: CsrEnrollResponse = try CodableCBORDecoder().decode(CsrEnrollResponse.self, from: swiftData)
        let rustResponse: CsrEnrollResponse = try CodableCBORDecoder().decode(CsrEnrollResponse.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftResponse, rustResponse, "CsrEnrollResponse validation failed - Swift and Rust data don't match")
    }

    private func validateRenewRequest(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("renew_request_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("renew_request_basic.bin"))

        // Verify both can be decoded correctly
        let swiftRequest: RenewRequest = try CodableCBORDecoder().decode(RenewRequest.self, from: swiftData)
        let rustRequest: RenewRequest = try CodableCBORDecoder().decode(RenewRequest.self, from: rustData)

        // Test serialization/deserialization round-trip for Swift data
        let encoder = CodableCBOREncoder()
        let swiftReencoded = try encoder.encode(swiftRequest)
        let swiftRoundTrip: RenewRequest = try CodableCBORDecoder().decode(RenewRequest.self, from: swiftReencoded)
        XCTAssertEqual(swiftRequest, swiftRoundTrip, "Swift RenewRequest round-trip serialization failed")

        // Test serialization/deserialization round-trip for Rust data
        let rustReencoded = try encoder.encode(rustRequest)
        let rustRoundTrip: RenewRequest = try CodableCBORDecoder().decode(RenewRequest.self, from: rustReencoded)
        XCTAssertEqual(rustRequest, rustRoundTrip, "Rust RenewRequest round-trip serialization failed")

        // Validate that both decoded objects have the expected structure
        XCTAssertEqual(swiftRequest.network_id, "test_network", "Swift RenewRequest network_id should match")
        XCTAssertEqual(rustRequest.network_id, "test_network", "Rust RenewRequest network_id should match")
        XCTAssertFalse(swiftRequest.csr_der.isEmpty, "Swift RenewRequest csr_der should not be empty")
        XCTAssertFalse(rustRequest.csr_der.isEmpty, "Rust RenewRequest csr_der should not be empty")
    }

    private func validateRenewResponse(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("renew_response_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("renew_response_basic.bin"))

        // Verify both can be decoded correctly
        let swiftResponse: RenewResponse = try CodableCBORDecoder().decode(RenewResponse.self, from: swiftData)
        let rustResponse: RenewResponse = try CodableCBORDecoder().decode(RenewResponse.self, from: rustData)

        // Test serialization/deserialization round-trip for Swift data
        let encoder = CodableCBOREncoder()
        let swiftReencoded = try encoder.encode(swiftResponse)
        let swiftRoundTrip: RenewResponse = try CodableCBORDecoder().decode(RenewResponse.self, from: swiftReencoded)
        XCTAssertEqual(swiftResponse, swiftRoundTrip, "Swift RenewResponse round-trip serialization failed")

        // Test serialization/deserialization round-trip for Rust data
        let rustReencoded = try encoder.encode(rustResponse)
        let rustRoundTrip: RenewResponse = try CodableCBORDecoder().decode(RenewResponse.self, from: rustReencoded)
        XCTAssertEqual(rustResponse, rustRoundTrip, "Rust RenewResponse round-trip serialization failed")

        // Validate that both decoded objects have the expected structure
        XCTAssertEqual(swiftResponse.network_id, "test_network", "Swift RenewResponse network_id should match")
        XCTAssertEqual(rustResponse.network_id, "test_network", "Rust RenewResponse network_id should match")
        XCTAssertFalse(swiftResponse.certificate_der.isEmpty, "Swift RenewResponse certificate_der should not be empty")
        XCTAssertFalse(rustResponse.certificate_der.isEmpty, "Rust RenewResponse certificate_der should not be empty")
        XCTAssertFalse(swiftResponse.issuing_ca_der.isEmpty, "Swift RenewResponse issuing_ca_der should not be empty")
        XCTAssertFalse(rustResponse.issuing_ca_der.isEmpty, "Rust RenewResponse issuing_ca_der should not be empty")
    }

    private func validateRevokeRequest(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("revoke_request_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("revoke_request_basic.bin"))

        let swiftRequest: RevokeRequest = try CodableCBORDecoder().decode(RevokeRequest.self, from: swiftData)
        let rustRequest: RevokeRequest = try CodableCBORDecoder().decode(RevokeRequest.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftRequest, rustRequest, "RevokeRequest validation failed - Swift and Rust data don't match")
    }

    private func validateRevokeResponse(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("revoke_response_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("revoke_response_basic.bin"))

        let swiftResponse: RevokeResponse = try CodableCBORDecoder().decode(RevokeResponse.self, from: swiftData)
        let rustResponse: RevokeResponse = try CodableCBORDecoder().decode(RevokeResponse.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftResponse, rustResponse, "RevokeResponse validation failed - Swift and Rust data don't match")
    }

    private func validateCaStatus(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("ca_status_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("ca_status_basic.bin"))

        // Verify both can be decoded correctly
        let swiftStatus: CaStatus = try CodableCBORDecoder().decode(CaStatus.self, from: swiftData)
        let rustStatus: CaStatus = try CodableCBORDecoder().decode(CaStatus.self, from: rustData)

        // Test serialization/deserialization round-trip for Swift data
        let encoder = CodableCBOREncoder()
        let swiftReencoded = try encoder.encode(swiftStatus)
        let swiftRoundTrip: CaStatus = try CodableCBORDecoder().decode(CaStatus.self, from: swiftReencoded)
        XCTAssertEqual(swiftStatus, swiftRoundTrip, "Swift CaStatus round-trip serialization failed")

        // Test serialization/deserialization round-trip for Rust data
        let rustReencoded = try encoder.encode(rustStatus)
        let rustRoundTrip: CaStatus = try CodableCBORDecoder().decode(CaStatus.self, from: rustReencoded)
        XCTAssertEqual(rustStatus, rustRoundTrip, "Rust CaStatus round-trip serialization failed")

        // Validate that both decoded objects have the expected structure
        XCTAssertEqual(swiftStatus.network_id, "test_network", "Swift CaStatus network_id should match")
        XCTAssertEqual(rustStatus.network_id, "test_network", "Rust CaStatus network_id should match")
        XCTAssertFalse(swiftStatus.issuing_subject.isEmpty, "Swift CaStatus issuing_subject should not be empty")
        XCTAssertFalse(rustStatus.issuing_subject.isEmpty, "Rust CaStatus issuing_subject should not be empty")
        XCTAssertFalse(swiftStatus.issuing_serial_hex.isEmpty, "Swift CaStatus issuing_serial_hex should not be empty")
        XCTAssertFalse(rustStatus.issuing_serial_hex.isEmpty, "Rust CaStatus issuing_serial_hex should not be empty")
    }

    private func validateChainResponse(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("chain_response_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("chain_response_basic.bin"))

        // Verify both can be decoded correctly
        let swiftResponse: ChainResponse = try CodableCBORDecoder().decode(ChainResponse.self, from: swiftData)
        let rustResponse: ChainResponse = try CodableCBORDecoder().decode(ChainResponse.self, from: rustData)

        // Test serialization/deserialization round-trip for Swift data
        let encoder = CodableCBOREncoder()
        let swiftReencoded = try encoder.encode(swiftResponse)
        let swiftRoundTrip: ChainResponse = try CodableCBORDecoder().decode(ChainResponse.self, from: swiftReencoded)
        XCTAssertEqual(swiftResponse, swiftRoundTrip, "Swift ChainResponse round-trip serialization failed")

        // Test serialization/deserialization round-trip for Rust data
        let rustReencoded = try encoder.encode(rustResponse)
        let rustRoundTrip: ChainResponse = try CodableCBORDecoder().decode(ChainResponse.self, from: rustReencoded)
        XCTAssertEqual(rustResponse, rustRoundTrip, "Rust ChainResponse round-trip serialization failed")

        // Validate that both decoded objects have the expected structure
        XCTAssertEqual(swiftResponse.network_id, "test_network", "Swift ChainResponse network_id should match")
        XCTAssertEqual(rustResponse.network_id, "test_network", "Rust ChainResponse network_id should match")
        XCTAssertFalse(swiftResponse.issuing_ca_der.isEmpty, "Swift ChainResponse issuing_ca_der should not be empty")
        XCTAssertFalse(rustResponse.issuing_ca_der.isEmpty, "Rust ChainResponse issuing_ca_der should not be empty")
        // Note: root_ca_der is optional, so we don't assert it's not empty
    }

    private func validateCaErrorResponse(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("ca_error_response_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("ca_error_response_basic.bin"))

        let swiftError: CaErrorResponse = try CodableCBORDecoder().decode(CaErrorResponse.self, from: swiftData)
        let rustError: CaErrorResponse = try CodableCBORDecoder().decode(CaErrorResponse.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftError, rustError, "CaErrorResponse validation failed - Swift and Rust data don't match")
    }

    /// Test all new transport types CBOR compatibility as required by task11.md
    func testNewTransportTypesCBORCompatibility() async throws {
        print("=== Testing New Transport Types CBOR Compatibility ===")
        // Note: QuicTransportOptions doesn't implement Serialize in Rust, so we skip it for now
        try await validatePeerInfo()
        // TransportEvent removed - replaced with typed event structs
        try await validateTransportRequestParams()
        try await validateTransportCompleteRequestParams()
        try await validateTransportPublishParams()
        print("=== All new transport types CBOR tests passed ===")
    }

    // MARK: - New Transport Types Validation (task11.md requirement)

    // QuicTransportOptions doesn't implement Serialize in Rust, so we skip it for now

    /// Test PeerInfo CBOR compatibility with Rust
    private func validatePeerInfo() async throws {
        let swiftDir = URL(fileURLWithPath: "target/ffi-types-vectors-swift")
        let rustDir = URL(fileURLWithPath: "../../runar-rust/rust-examples/target/ffi-types-vectors")

        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("peer_info_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("peer_info_basic.bin"))

        let swiftPeer: PeerInfo = try CodableCBORDecoder().decode(PeerInfo.self, from: swiftData)
        let rustPeer: PeerInfo = try CodableCBORDecoder().decode(PeerInfo.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftPeer, rustPeer, "PeerInfo validation failed - Swift and Rust data don't match")
    }

    // TransportEvent validation removed - replaced with typed event structs

    // MARK: - Typed Transport Events (Rust -> Swift validation)

    private func validatePeerConnectedEventRustToSwift(swiftDir _: URL, rustDir: URL) async throws {
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("peer_connected_event_basic.bin"))
        let event: PeerConnectedEvent = try CodableCBORDecoder().decode(PeerConnectedEvent.self, from: rustData)
        XCTAssertFalse(event.nodeId.isEmpty, "PeerConnectedEvent.nodeId should not be empty")
        // Basic sanity on NodeInfo
        XCTAssertFalse(event.nodeInfo.nodePublicKey.isEmpty, "PeerConnectedEvent.nodeInfo.nodePublicKey should not be empty")
    }

    private func validateTransportRequestEventRustToSwift(swiftDir _: URL, rustDir: URL) async throws {
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("transport_request_event_basic.bin"))
        let event: TransportRequestEvent = try CodableCBORDecoder().decode(TransportRequestEvent.self, from: rustData)
        XCTAssertEqual(event.path, "/echo")
        XCTAssertEqual(event.correlationId, "c1")
        XCTAssertEqual(event.payload, Data("hello".utf8))
        XCTAssertFalse(event.sourcePeerId.isEmpty, "sourcePeerId should not be empty")
        XCTAssertFalse(event.destinationPeerId.isEmpty, "destinationPeerId should not be empty")
    }

    private func validateTransportEventEventRustToSwift(swiftDir _: URL, rustDir: URL) async throws {
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("transport_event_event_basic.bin"))
        let event: TransportEventEvent = try CodableCBORDecoder().decode(TransportEventEvent.self, from: rustData)
        XCTAssertEqual(event.path, "/event")
        XCTAssertEqual(event.correlationId, "e1")
        XCTAssertEqual(event.payload, Data("evt".utf8))
        XCTAssertFalse(event.sourcePeerId.isEmpty, "sourcePeerId should not be empty")
        XCTAssertFalse(event.destinationPeerId.isEmpty, "destinationPeerId should not be empty")
    }

    private func validateTransportResponseEventRustToSwift(swiftDir _: URL, rustDir: URL) async throws {
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("transport_response_event_basic.bin"))
        let event: TransportResponseEvent = try CodableCBORDecoder().decode(TransportResponseEvent.self, from: rustData)
        XCTAssertEqual(event.correlationId, "c1")
        XCTAssertEqual(event.payload, Data("world".utf8))
    }

    /// Test TransportRequestParams CBOR compatibility with Rust
    private func validateTransportRequestParams() async throws {
        let swiftDir = URL(fileURLWithPath: "target/ffi-types-vectors-swift")
        let rustDir = URL(fileURLWithPath: "../../runar-rust/rust-examples/target/ffi-types-vectors")

        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("transport_request_params_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("transport_request_params_basic.bin"))

        let swiftRequest: TransportRequestParams = try CodableCBORDecoder().decode(TransportRequestParams.self, from: swiftData)
        let rustRequest: TransportRequestParams = try CodableCBORDecoder().decode(TransportRequestParams.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftRequest, rustRequest, "TransportRequestParams validation failed - Swift and Rust data don't match")
    }

    /// Test TransportCompleteRequestParams CBOR compatibility with Rust
    private func validateTransportCompleteRequestParams() async throws {
        let swiftDir = URL(fileURLWithPath: "target/ffi-types-vectors-swift")
        let rustDir = URL(fileURLWithPath: "../../runar-rust/rust-examples/target/ffi-types-vectors")

        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("transport_complete_request_params_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("transport_complete_request_params_basic.bin"))

        let swiftComplete: TransportCompleteRequestParams = try CodableCBORDecoder().decode(TransportCompleteRequestParams.self, from: swiftData)
        let rustComplete: TransportCompleteRequestParams = try CodableCBORDecoder().decode(TransportCompleteRequestParams.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftComplete, rustComplete, "TransportCompleteRequestParams validation failed - Swift and Rust data don't match")
    }

    /// Test TransportPublishParams CBOR compatibility with Rust
    private func validateTransportPublishParams() async throws {
        let swiftDir = URL(fileURLWithPath: "target/ffi-types-vectors-swift")
        let rustDir = URL(fileURLWithPath: "../../runar-rust/rust-examples/target/ffi-types-vectors")

        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("transport_publish_params_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("transport_publish_params_basic.bin"))

        let swiftPublish: TransportPublishParams = try CodableCBORDecoder().decode(TransportPublishParams.self, from: swiftData)
        let rustPublish: TransportPublishParams = try CodableCBORDecoder().decode(TransportPublishParams.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftPublish, rustPublish, "TransportPublishParams validation failed - Swift and Rust data don't match")
    }

    /// Test NetworkMessagePayloadItem CBOR compatibility with Rust
    private func validateNetworkMessagePayloadItem(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("network_message_payload_item_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("network_message_payload_item_basic.bin"))

        let swiftPayload: NetworkMessagePayloadItem = try CodableCBORDecoder().decode(NetworkMessagePayloadItem.self, from: swiftData)
        let rustPayload: NetworkMessagePayloadItem = try CodableCBORDecoder().decode(NetworkMessagePayloadItem.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftPayload, rustPayload, "NetworkMessagePayloadItem validation failed - Swift and Rust data don't match")
    }

    /// Test NetworkMessage CBOR compatibility with Rust
    private func validateNetworkMessage(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("network_message_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("network_message_basic.bin"))

        let swiftMessage: NetworkMessage = try CodableCBORDecoder().decode(NetworkMessage.self, from: swiftData)
        let rustMessage: NetworkMessage = try CodableCBORDecoder().decode(NetworkMessage.self, from: rustData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftMessage, rustMessage, "NetworkMessage validation failed - Swift and Rust data don't match")
    }

    /// Test NodeInfo CBOR compatibility with Rust
    private func validateNodeInfo(swiftDir: URL, rustDir: URL) async throws {
        // Test basic NodeInfo
        let swiftBasicData = try Data(contentsOf: swiftDir.appendingPathComponent("node_info_basic.bin"))
        let rustBasicData = try Data(contentsOf: rustDir.appendingPathComponent("node_info_basic.bin"))

        let swiftBasicNode: NodeInfo = try CodableCBORDecoder().decode(NodeInfo.self, from: swiftBasicData)
        let rustBasicNode: NodeInfo = try CodableCBORDecoder().decode(NodeInfo.self, from: rustBasicData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftBasicNode, rustBasicNode, "NodeInfo basic validation failed - Swift and Rust data don't match")

        // Test NodeInfo with metadata
        let swiftMetadataData = try Data(contentsOf: swiftDir.appendingPathComponent("node_info_with_metadata.bin"))
        let rustMetadataData = try Data(contentsOf: rustDir.appendingPathComponent("node_info_with_metadata.bin"))

        let swiftMetadataNode: NodeInfo = try CodableCBORDecoder().decode(NodeInfo.self, from: swiftMetadataData)
        let rustMetadataNode: NodeInfo = try CodableCBORDecoder().decode(NodeInfo.self, from: rustMetadataData)

        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftMetadataNode, rustMetadataNode, "NodeInfo with metadata validation failed - Swift and Rust data don't match")
    }
}
