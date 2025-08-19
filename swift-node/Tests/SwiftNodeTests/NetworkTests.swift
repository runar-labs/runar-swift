import XCTest
@testable import SwiftNode
import RunarSerializer
import SwiftCBOR

final class NetworkTests: XCTestCase {
    // Minimal transport stub to simulate PeerConnected/Disconnected and responses
    final class StubTransport: NodeTransport {
        var events: [Data] = []
        var started = false
        var capturedDestPeers: [String?] = []
        var respond: ((String, String, Data) -> Data?)? // (path, cid, payload) -> response payload
        var emitResponses: Bool = true
        func start() throws { started = true }
        func stop() throws { started = false }
        func pollEvent() throws -> Data? { events.isEmpty ? nil : events.removeFirst() }
        func request(path: String, correlationId: String, payload: Data, destPeerId: String?, profilePublicKey: Data?) throws {
            capturedDestPeers.append(destPeerId)
            guard emitResponses else { return }
            // Compute payload and emit ResponseReceived
            let respPayload = respond?(path, correlationId, payload) ?? payload
            struct ResponseEvent: Codable { let type: String; let v: UInt64; let correlation_id: String; let payload: Data }
            let event = ResponseEvent(type: "ResponseReceived", v: 1, correlation_id: correlationId, payload: respPayload)
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
        // Helpers to enqueue peer lifecycle events
        func enqueuePeerConnected(peerId: String, services: [String]? = nil) {
            struct E: Codable { let type: String; let v: UInt64; let peer_node_id: String; let services: [String]? }
            let e = E(type: "PeerConnected", v: 1, peer_node_id: peerId, services: services)
            let data = try! CodableCBOREncoder().encode(e)
            events.append(data)
        }
        func enqueuePeerDisconnected(peerId: String) {
            struct E: Codable { let type: String; let v: UInt64; let peer_node_id: String }
            let e = E(type: "PeerDisconnected", v: 1, peer_node_id: peerId)
            let data = try! CodableCBOREncoder().encode(e)
            events.append(data)
        }
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

    func testPeerConnectedRegistersServicesAndRoutesRequests() async throws {
        let stub = StubTransport()
        // Respond to $registry/services/list with service metadata for svc
        stub.respond = { path, _, _ in
            if path.contains("$registry/services/list") {
                let now = UInt64(Date().timeIntervalSince1970)
                let meta = RegistryServiceMetadata(
                    network_id: "net",
                    service_path: "svc",
                    name: "RemoteEcho",
                    version: "0.0.1",
                    description: "remote",
                    registration_time: now,
                    last_start_time: now
                )
                let any = AnyValue.struct([meta])
                return try? any.serialize(context: nil)
            }
            return nil
        }
        let node = SwiftNode(config: .init(defaultNetworkId: "net"), transport: stub)
        try await node.start()
        // Notify peer connected
        stub.enqueuePeerConnected(peerId: "peer1", services: ["svc"]) // provide services inline
        // Issue a request to remote service; should select peer1 as destination
        _ = try await node.request("svc/remote_action", payload: AnyValue.primitive(1))
        XCTAssertEqual(stub.capturedDestPeers.last ?? nil, "peer1")
        await node.stop()
    }

    func testRoundRobinAcrossPeers() async throws {
        let stub = StubTransport()
        stub.respond = { path, _, _ in
            if path.contains("$registry/services/list") {
                let now = UInt64(Date().timeIntervalSince1970)
                let meta = RegistryServiceMetadata(
                    network_id: "net",
                    service_path: "svc",
                    name: "RemoteEcho",
                    version: "0.0.1",
                    description: "remote",
                    registration_time: now,
                    last_start_time: now
                )
                let any = AnyValue.struct([meta])
                return try? any.serialize(context: nil)
            }
            return nil
        }
        let node = SwiftNode(config: .init(defaultNetworkId: "net"), transport: stub)
        try await node.start()
        stub.enqueuePeerConnected(peerId: "peerA", services: ["svc"]) // both advertise svc
        stub.enqueuePeerConnected(peerId: "peerB", services: ["svc"]) 
        _ = try await node.request("svc/do1", payload: AnyValue.null())
        _ = try await node.request("svc/do2", payload: AnyValue.null())
        let lastTwo = Array(stub.capturedDestPeers.suffix(2))
        XCTAssertEqual(lastTwo.count, 2)
        let a = lastTwo[0]
        let b = lastTwo[1]
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertNotEqual(a!, b!)
        await node.stop()
    }

    func testPublishBroadcasts() async throws {
        let stub = StubTransport()
        let node = SwiftNode(config: .init(defaultNetworkId: "net"), transport: stub)
        try await node.start()
        try await node.publish("default/topic", data: AnyValue.null())
        // publish should not select a dest peer (broadcast)
        // We cannot observe directly; ensure request path never invoked with publish behavior; no assertion here other than no crash
        await node.stop()
    }

    func testRequestTimeoutWhenNoResponse() async throws {
        let stub = StubTransport()
        stub.emitResponses = false
        let node = SwiftNode(config: .init(defaultNetworkId: "net", requestTimeoutMs: 50), transport: stub)
        try await node.start()
        do {
            _ = try await node.request("svc/willtimeout", payload: AnyValue.null())
            XCTFail("expected timeout error")
        } catch {
            // ok
        }
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


