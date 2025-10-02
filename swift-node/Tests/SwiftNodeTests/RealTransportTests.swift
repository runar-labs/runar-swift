import RunarSerializer
import SwiftCBOR
import SwiftCommon
@testable import SwiftNode
import XCTest

@MainActor
final class RealTransportTests: XCTestCase {
    final class EchoService: AbstractService {
        var name: String { "Echo" }
        var version: String { "0.0.1" }
        var path: String { "svc" }
        var description: String { "test" }
        var networkId: String?
        var state: ServiceState = .created
        var logger: RunarLogger = .root(component: .service)
        func initService(_ ctx: LifecycleContext) async throws {
            try await ctx.registerAction("echo") { payload, requestContext in
                payload ?? AnyValue.null()
            }
        }

        func start(_: LifecycleContext) async throws {}
        func stop(_: LifecycleContext) async throws {}
        
        func setNetworkId(_ networkId: String) {
            self.networkId = networkId
        }
    }

    func testTwoNodesRequestRoundTrip() async throws {
        // TODO: Fix RunarTestUtils dependency - test disabled for now
        // This test requires RunarTestUtils which is not available
    }
}
