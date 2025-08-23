import RunarSerializer
import SwiftCommon
@testable import SwiftNode
import XCTest

@MainActor
final class SwiftNodeTests: XCTestCase {
    func testLocalActionAndRequest() async throws {
        let node = SwiftNode(config: .init(defaultNetworkId: "net"))
        final class EchoService: AbstractService {
            var name: String { "echo" }
            var version: String { "1.0.0" }
            var path: String { "echo" }
            var description: String { "echo service" }
            var networkId: String?
            var state: ServiceState = .created
            var logger: RunarLogger = .init(component: .service)
            func initService(_ context: LifecycleContext) async throws {
                try await context.registerAction("say") { params, _ in
                    params ?? AnyValue.null()
                }
            }

            func start(_: LifecycleContext) async throws {}
            func stop(_: LifecycleContext) async throws {}
        }
        try await node.addService(EchoService())
        try await node.start()
        let res = try await node.request("echo/say", payload: AnyValue.primitive("hello"))
        let text: String = try await res.asType()
        XCTAssertEqual(text, "hello")
    }

    func testRegistryServicesList() async throws {
        let node = SwiftNode(config: .init(defaultNetworkId: "net"))
        final class Svc: AbstractService {
            var name: String { "svc" }
            var version: String { "0.1.0" }
            var path: String { "svc" }
            var description: String { "svc desc" }
            var networkId: String?
            var state: ServiceState = .created
            var logger: RunarLogger = .init(component: .service)
            func initService(_: LifecycleContext) async throws {}
            func start(_: LifecycleContext) async throws {}
            func stop(_: LifecycleContext) async throws {}
        }
        try await node.addService(Svc())
        try await node.start()
        let res = try await node.request("$registry/services/list", payload: nil)
        let list: [RegistryServiceMetadata] = try await res.asType()
        XCTAssertTrue(list.contains(where: { $0.service_path == "svc" && $0.name == "svc" }))
    }

    func testPublishSubscribeDirect() async throws {
        let node = SwiftNode(config: .init(defaultNetworkId: "net"))
        try await node.start()
        let exp = expectation(description: "recv")
        _ = try await node.subscribe("echo/data", options: nil) { _, data in
            if let d = data {
                let val: String = try await d.asType()
                if val == "ping" { exp.fulfill() }
            }
        }
        try await node.publish("echo/data", data: AnyValue.primitive("ping"))
        await fulfillment(of: [exp], timeout: 2.0)
    }

    func testActionPublishesEvent() async throws {
        let node = SwiftNode(config: .init(defaultNetworkId: "net"))
        final class PubService: AbstractService {
            var name: String { "pub" }
            var version: String { "1.0.0" }
            var path: String { "pub" }
            var description: String { "pub service" }
            var networkId: String?
            var state: ServiceState = .created
            var logger: RunarLogger = .init(component: .service)
            func initService(_ context: LifecycleContext) async throws {
                try await context.registerAction("trigger") { _, ctx in
                    try await ctx.nodeDelegate.publish(topic: "pub/evt", data: AnyValue.primitive("event"))
                    return AnyValue.null()
                }
            }

            func start(_: LifecycleContext) async throws {}
            func stop(_: LifecycleContext) async throws {}
        }
        try await node.addService(PubService())
        try await node.start()
        let exp = expectation(description: "evt")
        _ = try await node.subscribe("pub/evt", options: nil) { _, data in
            if let d = data {
                let val: String = try await d.asType()
                if val == "event" { exp.fulfill() }
            }
        }
        _ = try await node.request("pub/trigger", payload: nil)
        await fulfillment(of: [exp], timeout: 2.0)
    }
}
