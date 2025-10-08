import RunarSerializer
import SwiftCommon
import SwiftFFI
@testable import SwiftNode
import XCTest

@MainActor
final class SwiftNodeTests: XCTestCase {
    // Swift logger for trace-level logging
    private var testLogger: RunarLogger!

    override func setUp() async throws {
        try await super.setUp()

        // Set global logger config to trace level for all tests
        LoggerConfigManager.shared.globalConfig = LoggerConfig(
            level: .trace,
            includeTimestamp: true,
            includeComponent: true,
            includeContext: true
        )

        // Create root logger for this test with test name as context
        testLogger = RunarLogger.root(component: .custom("SwiftNodeTests"))
    }

    func testLocalActionAndRequest() async throws {
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "net")
            .withKeyManager(keysManager)
        let node = try await Node.new(config: config)
        final class EchoService: AbstractService {
            var name: String { "echo" }
            var version: String { "1.0.0" }
            var path: String { "echo" }
            var description: String { "echo service" }
            var networkId: String?
            var state: ServiceState = .created
            var logger: RunarLogger

            init(logger: RunarLogger) {
                self.logger = logger
            }

            func initService(_ context: LifecycleContext) async throws {
                try await context.registerAction("say") { payload, _ in
                    payload ?? AnyValue.null()
                }
            }

            func start(_: LifecycleContext) async throws {}
            func stop(_: LifecycleContext) async throws {}

            func setNetworkId(_ networkId: String) {
                self.networkId = networkId
            }
        }
        try await node.addService(EchoService(logger: testLogger.child(component: .custom("EchoService"))))
        try await node.start()
        try await node.waitForServicesToStart()
        let res = try await node.request("echo/say", payload: AnyValue.primitive("hello"))
        let text: String = try await res.asType()
        XCTAssertEqual(text, "hello")
    }

    func testRegistryServicesList() async throws {
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "net")
            .withKeyManager(keysManager)
        let node = try await Node.new(config: config)
        final class Svc: AbstractService {
            var name: String { "svc" }
            var version: String { "0.1.0" }
            var path: String { "svc" }
            var description: String { "svc desc" }
            var networkId: String?
            var state: ServiceState = .created
            var logger: RunarLogger = .root(component: .service)
            func initService(_: LifecycleContext) async throws {}
            func start(_: LifecycleContext) async throws {}
            func stop(_: LifecycleContext) async throws {}

            func setNetworkId(_ networkId: String) {
                self.networkId = networkId
            }
        }
        try await node.addService(Svc())
        try await node.start()
        let res = try await node.request("$registry/services/list", payload: AnyValue.map([
            "include_internal_services": AnyValue.primitive(true),
            "include_remote_services": AnyValue.primitive(true)
        ]))
        let listArray = try await res.asType() as [AnyValue]
        var list: [ServiceMetadata] = []
        for av in listArray {
            let service = try await av.asType() as ServiceMetadata
            list.append(service)
        }
        XCTAssertTrue(list.contains(where: { $0.servicePath == "svc" && $0.name == "svc" }))
    }

    func testPublishSubscribeDirect() async throws {
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "net")
            .withKeyManager(keysManager)
        let node = try await Node.new(config: config)
        try await node.start()
        let exp = expectation(description: "recv")
        _ = try await node.subscribe(topic: "echo/data", options: nil as EventRegistrationOptions?) { eventContext, data in
            if let d = data {
                let val: String? = try? await d.asType() as String
                if val == "ping" { exp.fulfill() }
            }
        }
        try await node.publish(topic: "echo/data", data: AnyValue.primitive("ping"))
        await fulfillment(of: [exp], timeout: 2.0)
    }

    func testActionPublishesEvent() async throws {
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "net")
            .withKeyManager(keysManager)
        let node = try await Node.new(config: config)
        final class PubService: AbstractService {
            var name: String { "pub" }
            var version: String { "1.0.0" }
            var path: String { "pub" }
            var description: String { "pub service" }
            var networkId: String?
            var state: ServiceState = .created
            var logger: RunarLogger = .root(component: .service)
            func initService(_ context: LifecycleContext) async throws {
                try await context.registerAction("trigger") { _, _ in
                    // Publish an event when the action is called
                    try await context.nodeDelegate.publish(topic: "pub/evt", data: AnyValue.primitive("event"))
                    return AnyValue.primitive("triggered")
                }
            }

            func start(_: LifecycleContext) async throws {}
            func stop(_: LifecycleContext) async throws {}

            func setNetworkId(_ networkId: String) {
                self.networkId = networkId
            }
        }
        try await node.addService(PubService())
        try await node.start()
        try await node.waitForServicesToStart()
        let exp = expectation(description: "evt")
        _ = try await node.subscribe(topic: "pub/evt", options: nil as EventRegistrationOptions?) { eventContext, data in
            if let d = data {
                let val: String? = try? await d.asType() as String
                if val == "event" { exp.fulfill() }
            }
        }
        _ = try await node.request("pub/trigger", payload: nil as AnyValue?)
        await fulfillment(of: [exp], timeout: 2.0)
    }
}
