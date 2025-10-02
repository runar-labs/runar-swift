import RunarSerializer
import SwiftCommon
@testable import SwiftNode
import XCTest

@MainActor
final class NetworkTests: XCTestCase {
    final class PubService: AbstractService {
        var name: String { "Pub" }
        var version: String { "0.0.1" }
        var path: String { "pub" }
        var description: String { "test" }
        var networkId: String?
        var state: ServiceState = .created
        var logger: RunarLogger = .root(component: .service)
        func initService(_ ctx: LifecycleContext) async throws {
            try await ctx.registerAction("trigger") { payload, requestContext in
                try await ctx.nodeDelegate.publish(topic: "pub/evt", data: AnyValue.primitive("hi"))
                return AnyValue.null()
            }
        }

        func start(_: LifecycleContext) async throws {}
        func stop(_: LifecycleContext) async throws {}
        
        func setNetworkId(_ networkId: String) {
            self.networkId = networkId
        }
    }

    func testPublishSubscribeOverNetwork() async throws {
        // TODO: Fix RunarTestUtils dependency - test disabled for now
        // This test requires RunarTestUtils which is not available
        /*
        // CA + two node keys with certificates
        let can = try RunarTestUtils.TestFixtures.createCAAndNodes(count: 2, addresses: ["127.0.0.1:50621", "127.0.0.1:50622"], defaultNetworkId: "net")
        let keys1 = can.nodes[0]
        let keys2 = can.nodes[1]

        // Nodes with injected keys (set internal event retention for tests)
        let n1 = try await Node.new(config: .init(defaultNetworkId: can.defaultNetworkId))
        let n2 = try await Node.new(config: .init(defaultNetworkId: can.defaultNetworkId))
        try await n1.addService(PubService())
        try await n1.start()
        try await n2.start()

        // Connect peers
        let p1 = try await n1.exportPeerInfoCBOR()
        var lastError: Error?
        for _ in 0 ..< 5 {
            do { try await n2.connectPeer(p1); lastError = nil; break } catch { lastError = error; try? await Task.sleep(nanoseconds: 200_000_000) }
        }
        if let e = lastError { throw e }

        // Wait for discovered event via on(...)
        let nid1 = try keys1.nodeId()
        let topic = "$registry/peer/\(nid1)/discovered"
        let handle = n2.on(topic, options: OnOptions(timeout: 20.0, includePast: 20.0))
        let res = await handle.value()
        switch res {
        case .success:
            break
        case let .failure(err):
            XCTFail("did not receive discovered event: \(err)")
        }

        // Subscribe on node2, trigger publish on node1
        let exp = expectation(description: "recv")
        _ = try await n2.subscribe("pub/evt", options: EventRegistrationOptions(includePast: 10.0)) { _, v in
            let s: String? = try? await v?.asType()
            if s == "hi" { exp.fulfill() }
        }
        // Small delay to ensure subscription is fully established
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        try await n1.publish("pub/evt", data: AnyValue.primitive("hi"), retainFor: 10.0)
        await fulfillment(of: [exp], timeout: 5.0)

        await n2.stop()
        await n1.stop()
        */
    }
}

// Removed stub-based tests; real transport tests live in RealTransportTests.swift
