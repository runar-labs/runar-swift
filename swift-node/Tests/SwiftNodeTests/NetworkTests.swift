import XCTest
@testable import SwiftNode

final class NetworkTests: XCTestCase {
    final class PubService: AbstractService {
        var name: String { "Pub" }
        var version: String { "0.0.1" }
        var path: String { "pub" }
        var description: String { "test" }
        var networkId: String? = nil
        func initService(_ ctx: LifecycleContext) async throws {
            try await ctx.registerAction("trigger") { params, ctx in
                try await ctx.publish("pub/evt", AnyValue.primitive("hi"))
                return AnyValue.null()
            }
        }
        func start(_ context: LifecycleContext) async throws {}
        func stop(_ context: LifecycleContext) async throws {}
    }

    func testPublishSubscribeOverNetwork() async throws {
        // Start two nodes back-to-back
        let n1 = SwiftNode(config: .init(defaultNetworkId: "net", network: .init(enabled: true, bindAddress: "127.0.0.1:50621")))
        let n2 = SwiftNode(config: .init(defaultNetworkId: "net", network: .init(enabled: true, bindAddress: "127.0.0.1:50622")))
        try await n1.addService(PubService())
        try await n1.start()
        try await n2.start()

        // Build peer info and connect
        let p1 = try n1.exportPeerInfoCBOR()
        var lastError: Error?
        for _ in 0..<5 { do { try n2.connectPeer(p1); lastError = nil; break } catch { lastError = error; try? await Task.sleep(nanoseconds: 200_000_000) } }
        if let e = lastError { throw e }

        // Subscribe on node2, trigger publish on node1
        let exp = expectation(description: "recv")
        _ = try await n2.subscribe("pub/evt") { _, v in
            let s: String? = try? await v?.asType()
            if s == "hi" { exp.fulfill() }
        }
        _ = try await n1.request("pub/trigger", payload: nil)
        wait(for: [exp], timeout: 5.0)

        await n2.stop()
        await n1.stop()
    }
}

// Removed stub-based tests; real transport tests live in RealTransportTests.swift


