import XCTest
@testable import SwiftNode
import RunarSerializer

final class SwiftNodeTests: XCTestCase {
	func testLocalActionAndRequest() async throws {
		let node = SwiftNode(config: .init(defaultNetworkId: "net"))
		final class EchoService: AbstractService {
			var name: String { "echo" }
			var version: String { "1.0.0" }
			var path: String { "echo" }
			var description: String { "echo service" }
			var networkId: String?
			func initService(_ context: LifecycleContext) async throws {
				try await context.registerAction("say") { params, _ in
					return params ?? AnyValue.null()
				}
			}
			func start(_ context: LifecycleContext) async throws {}
			func stop(_ context: LifecycleContext) async throws {}
		}
		try await node.addService(EchoService())
		let res = try await node.request("echo/say", payload: AnyValue.primitive("hello"))
		let text: String = try await res.asType()
		XCTAssertEqual(text, "hello")
	}
}
