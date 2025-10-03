import SwiftCBOR
import SwiftCommon
import SwiftFFI
import XCTest

/// Test manual polling for events to debug the polling issue
@testable import SwiftFFI

@MainActor
final class ManualPollingTest: XCTestCase {
    /// Test manual polling for events - exactly like Rust test
    func testManualPollingForEvents() async throws {
        // Set up logging to match Rust test
        try await FFILogger.setLogLevel(.trace)
        try await FFILogger.setLoggerContext("manual-polling-test")

        // Step 1: Create two node key managers (A and B) - exactly like Rust
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()

        // Step 2: Create mobile key manager for CA (Certificate Authority) - exactly like Rust
        let keysCA = try await MobileKeyManager()

        // Step 3: Set node info for both nodes - exactly like Rust
        let nodeInfo = NodeInfo(
            nodePublicKey: Data(),
            networkIds: ["test_network"],
            addresses: ["127.0.0.1:0"],
            nodeMetadata: NodeMetadata(services: [], subscriptions: []),
            version: 1
        )
        let nodeInfoCbor = try CodableCBOREncoder().encode(nodeInfo)

        // Note: NodeInfo is now set on the transport, not on keys
        // This will be set when creating the transport

        // Step 4: Generate CSR for node A and process through mobile CA - exactly like Rust
        let csrA = try await keysA.generateCsrSetupToken()
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)

        // Step 5: Generate CSR for node B and process through mobile CA - exactly like Rust
        let csrB = try await keysB.generateCsrSetupToken()
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)

        // Step 6: Create transport options - exactly like Rust
        let transportOptions = QuicTransportOptions(
            requestTimeoutSeconds: 30,
            bindAddr: "127.0.0.1:0"
        )

        // Step 7: Create transport A with minimal callbacks
        let callbacksA = TransportCallbacks(
            requestCallback: { receivedRequestId, path, _, sourcePeerId, correlationId in
                print("ManualPollingTest - Request received on A: \(receivedRequestId)")

                // Create a NetworkMessage response
                let responsePayload = NetworkMessagePayloadItem(
                    path: path,
                    payloadBytes: Data("world".utf8),
                    correlationId: correlationId ?? "test_correlation",
                    networkPublicKey: nil,
                    profilePublicKeys: []
                )

                let responseMessage = NetworkMessage(
                    sourceNodeId: "test_node_a",
                    destinationNodeId: sourcePeerId,
                    messageType: 5, // MESSAGE_TYPE_RESPONSE
                    payload: responsePayload
                )

                return responseMessage
            }
        )

        // Step 8: Create transport A and start it
        let loggerA = RunarLogger.root(component: .custom("ManualPollingTest"))
        let transportA = try await QuicTransport.create(keys: keysA, nodeInfo: nodeInfo, options: transportOptions, callbacks: callbacksA, logger: loggerA)
        try await transportA.start()

        // Step 9: Get local address for transport A
        let localAddrA = try await transportA.getLocalAddr()
        XCTAssertFalse(localAddrA.isEmpty, "Local address should not be empty")

        // Step 10: Create transport B with minimal callbacks
        let callbacksB = TransportCallbacks(
            requestCallback: { _, _, _, _, _ in
                NetworkMessage(
                    sourceNodeId: "",
                    destinationNodeId: "",
                    messageType: 5, // MESSAGE_TYPE_RESPONSE
                    payload: NetworkMessagePayloadItem(
                        path: "",
                        payloadBytes: Data(),
                        correlationId: "",
                        networkPublicKey: nil,
                        profilePublicKeys: []
                    )
                )
            }
        )

        // Step 11: Create transport B and start it
        let loggerB = RunarLogger.root(component: .custom("ManualPollingTest"))
        let transportB = try await QuicTransport.create(keys: keysB, nodeInfo: nodeInfo, options: transportOptions, callbacks: callbacksB, logger: loggerB)
        try await transportB.start()

        // Step 12: Get public key for node A
        let publicKeyA = try await keysA.getNodePublicKey()

        // Step 13: Generate peer ID using compact ID
        let peerId = try await keysA.getCompactId(for: publicKeyA)

        // Step 14: Create peer info for connection
        let peerInfo = PeerInfo(publicKey: publicKeyA, addresses: [localAddrA])

        // Step 15: Connect transport B to transport A
        try await transportB.connectPeer(peerInfo: peerInfo)

        // Step 16: Create request parameters
        let requestParams = TransportRequestParams(
            path: "/echo",
            correlationId: "c1",
            payload: Data("hello".utf8),
            destPeerId: peerId,
            networkPublicKey: nil,
            profilePublicKeys: []
        )

        // Step 17: Send request from transport B and get response directly
        // This matches the Rust architecture where request() waits internally for the response
        print("ManualPollingTest - Sending request and waiting for response...")
        let responseData = try await transportB.request(requestParams)

        // Verify we got the expected response (now a CBOR-serialized NetworkMessage)
        do {
            let responseMessage: NetworkMessage = try CodableCBORDecoder().decode(NetworkMessage.self, from: responseData)
            XCTAssertEqual(responseMessage.payload.payloadBytes, Data("world".utf8), "Should have received correct response payload")
            XCTAssertEqual(responseMessage.messageType, 5, "Should be a response message type")
            print("ManualPollingTest - Received response: \(String(data: responseMessage.payload.payloadBytes, encoding: .utf8) ?? "")")
        } catch {
            XCTFail("Failed to deserialize NetworkMessage response: \(error)")
        }

        // Step 18: Verify that transport A received the request (this should be handled by callbacks)
        // The request callback on transport A should have been called and returned the response
        // This is verified by the fact that we received the correct response above

        // Step 20: Cleanup
        try await transportA.stop()
        try await transportB.stop()
    }
}
