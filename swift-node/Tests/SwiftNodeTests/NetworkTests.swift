import XCTest
@testable import SwiftNode
import RunarSerializer
import RunarTestUtils

@MainActor
final class NetworkTests: XCTestCase {
    final class PubService: AbstractService {
        var name: String { "Pub" }
        var version: String { "0.0.1" }
        var path: String { "pub" }
        var description: String { "test" }
        var networkId: String? = nil
        func initService(_ ctx: LifecycleContext) async throws {
            try await ctx.registerAction("trigger") { params, ctx in
                try await ctx.nodeDelegate.publish(topic: "pub/evt", data: AnyValue.primitive("hi"))
                return AnyValue.null()
            }
        }
        func start(_ context: LifecycleContext) async throws {}
        func stop(_ context: LifecycleContext) async throws {}
    }

    func testPublishSubscribeOverNetwork() async throws {
        // CA + two node keys with certificates
        let can = try TestFixtures.createCAAndNodes(count: 2, addresses: ["127.0.0.1:50621", "127.0.0.1:50622"], defaultNetworkId: "net")
        let keys1 = can.nodes[0]
        let keys2 = can.nodes[1]

        // Nodes with injected keys
        let n1 = SwiftNode(config: .init(defaultNetworkId: can.defaultNetworkId, network: .init(enabled: true, bindAddress: "127.0.0.1:50621")), keys: keys1)
        let n2 = SwiftNode(config: .init(defaultNetworkId: can.defaultNetworkId, network: .init(enabled: true, bindAddress: "127.0.0.1:50622")), keys: keys2)
        try await n1.addService(PubService())
        try await n1.start()
        try await n2.start()

        // Connect peers
        let p1 = try await n1.exportPeerInfoCBOR()
        var lastError: Error?
        for _ in 0..<5 { do { try await n2.connectPeer(p1); lastError = nil; break } catch { lastError = error; try? await Task.sleep(nanoseconds: 200_000_000) } }
        if let e = lastError { throw e }

        // Subscribe on node2, trigger publish on node1
        let exp = expectation(description: "recv")
        _ = try await n2.subscribe("pub/evt") { _, v in
            let s: String? = try? await v?.asType()
            if s == "hi" { exp.fulfill() }
        }
        // Retain for a short period to tolerate race with subscription binding
        try await n1.publish("pub/evt", data: AnyValue.primitive("hi"), retainFor: 2.0)
        await fulfillment(of: [exp], timeout: 5.0)

        await n2.stop()
        await n1.stop()
    }
}

// Removed stub-based tests; real transport tests live in RealTransportTests.swift


