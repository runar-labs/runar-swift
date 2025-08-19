import XCTest
@testable import SwiftNode
import RunarFFI
import RunarSerializer
import RunarTestUtils

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
        // Keys (single lifecycle per node)
        let keysA = try TestFixtures.createKeyManagerWithCert()
        let keysB = try TestFixtures.createKeyManagerWithCert()
        // Node A (inject keys so start() uses them)
        let nodeA = SwiftNode(config: .init(defaultNetworkId: "net", network: .init(enabled: true, bindAddress: "127.0.0.1:0")), keys: keysA)
        try await nodeA.addService(EchoService())
        try await nodeA.start()
        // Node B
        let nodeB = SwiftNode(config: .init(defaultNetworkId: "net", network: .init(enabled: true, bindAddress: "127.0.0.1:0")), keys: keysB)
        try await nodeB.start()
        // Export peer info from A and connect B
        let peerInfoA = try nodeA.exportPeerInfoCBOR()
        try nodeB.connectPeer(peerInfoA)
        // Simple request to A's local svc from B (over network)
        let result = try await nodeB.request("svc/echo", payload: .primitive("hello"))
        let s: String = try await result.asType()
        XCTAssertEqual(s, "hello")
        await nodeB.stop()
        await nodeA.stop()
        _ = keysA; _ = keysB // ensure not optimized out (kept alive)
    }
}


