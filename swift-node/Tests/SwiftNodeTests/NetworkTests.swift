import XCTest
@testable import SwiftNode
import RunarSerializer
import SwiftCBOR

final class NetworkTests: XCTestCase {
    // Minimal transport stub to simulate PeerConnected/Disconnected and responses
    final class StubTransport: NodeTransport {
        var events: [Data] = []
        var started = false
        func start() throws { started = true }
        func stop() throws { started = false }
        func pollEvent() throws -> Data? { events.isEmpty ? nil : events.removeFirst() }
        func request(path: String, correlationId: String, payload: Data, destPeerId: String?, profilePublicKey: Data?) throws {
            // Immediately echo back a ResponseReceived with same correlationId using Codable CBOR
            struct ResponseEvent: Codable { let type: String; let v: UInt64; let correlation_id: String; let payload: Data }
            let event = ResponseEvent(type: "ResponseReceived", v: 1, correlation_id: correlationId, payload: payload)
            let enc = CodableCBOREncoder()
            let data = try! enc.encode(event)
            events.append(data)
        }
        func publish(path: String, correlationId: String, payload: Data, destPeerId: String?) throws {}
        func completeRequest(requestId: String, responsePayload: Data, profilePublicKey: Data?) throws {}
        func connectPeer(_ peerInfoCBOR: Data) throws {}
        func disconnectPeer(_ peerNodeId: String) throws {}
        func isConnected(_ peerNodeId: String) throws -> Bool { true }
        func updateLocalNodeInfo(_ nodeInfoCBOR: Data) throws {}
    }

    func testStubTransportRequestRoundTrip() async throws {
        let stub = StubTransport()
        let node = SwiftNode(config: .init(defaultNetworkId: "net"), transport: stub)
        try await node.addService(TestService())
        try await node.start()
        let result = try await node.request("svc/echo", payload: AnyValue.primitive("hi"))
        let str: String = try await result.asType()
        XCTAssertEqual(str, "hi")
        await node.stop()
    }
}

// Simple service used by tests
final class TestService: AbstractService {
    var name: String { "Echo" }
    var version: String { "0.0.1" }
    var path: String { "svc" }
    var description: String { "test" }
    var networkId: String? = nil
    func initService(_ ctx: LifecycleContext) async throws {
        try await ctx.registerAction("echo") { params, _ in
            return params ?? AnyValue.null()
        }
    }
    func start(_ context: LifecycleContext) async throws {}
    func stop(_ context: LifecycleContext) async throws {}
}


