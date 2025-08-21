import XCTest
@testable import SwiftNode
import RunarFFI
import RunarSerializer
import RunarTestUtils
import SwiftCBOR

@MainActor
final class RealTransportTests: XCTestCase {
    final class EchoService: AbstractService {
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
    func testTwoNodesRequestRoundTrip() async throws {
        // Build two nodes with CA-signed certs using test fixtures
        let fixture = try RunarTestUtils.TestFixtures.createCAAndNodes(count: 2, addresses: ["127.0.0.1:0", "127.0.0.1:0"], defaultNetworkId: "net")
        let keysA = fixture.nodes[0]
        let keysB = fixture.nodes[1]
        // Node A (inject keys so start() uses them)
        let nodeA = SwiftNode(config: .init(defaultNetworkId: fixture.defaultNetworkId, network: .init(enabled: true, bindAddress: "127.0.0.1:50611")), keys: keysA)
        try await nodeA.addService(EchoService())
        try await nodeA.start()
        _ = try await nodeA.exportPeerInfoCBOR()
        // Node B
        let nodeB = SwiftNode(config: .init(defaultNetworkId: fixture.defaultNetworkId, network: .init(enabled: true, bindAddress: "127.0.0.1:50612")), keys: keysB)
        try await nodeB.start()
        _ = try await nodeB.exportPeerInfoCBOR()
        // Export peer info from A and connect B, with retry/backoff
        let peerInfoA = try await nodeA.exportPeerInfoCBOR()
        try? await Task.sleep(nanoseconds: 200_000_000)
        var lastError: Error?
        for _ in 0..<5 {
            do { try await nodeB.connectPeer(peerInfoA); lastError = nil; break } catch { lastError = error; try? await Task.sleep(nanoseconds: 300_000_000) }
        }
        if let e = lastError { throw e }
        // Wait a brief moment for connection establishment metadata propagation
        try? await Task.sleep(nanoseconds: 200_000_000)
        // Simple request to A's local svc from B (over network)
        let result = try await nodeB.requestToPeer("svc/echo", payload: AnyValue.primitive("hello"), peerNodeId: try fixture.nodeIds[0])
        let s: String = try await result.asType()
        XCTAssertEqual(s, "hello")
        await nodeB.stop()
        await nodeA.stop()
    }
}


