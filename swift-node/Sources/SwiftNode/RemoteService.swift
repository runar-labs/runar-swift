import Foundation
import RunarFFI
import RunarSerializer
import SwiftCommon

// MARK: - Remote Service

/// RemoteService handles remote service proxying and discovery
/// This service manages remote service discovery, request routing, and response handling
@MainActor
public final class RemoteService: ServiceBase {
    private let nodeId: String
    private var serviceRegistry: ServiceRegistry
    public init(logger: RunarLogger = RunarLogger(component: .service), nodeId: String, serviceRegistry: ServiceRegistry) {
        self.nodeId = nodeId
        self.serviceRegistry = serviceRegistry
        super.init(name: "$remote", version: "1.0.0", path: "$remote", description: "Remote service proxying and discovery", logger: logger)
    }

    // MARK: - Service Lifecycle

    override public func performInitService(_ context: LifecycleContext) async throws {
        networkId = context.networkId
        // Remote services don't need node delegate - they use network transport directly
        // (matches Rust implementation)
    }

    override public func performStart(_ context: LifecycleContext) async throws {
        // Remote services don't register actions - they just proxy requests
        // No action registration needed (matches Rust implementation)
        // No load balancer needed (not in Rust implementation)
    }

    override public func performStop(_: LifecycleContext) async throws {
        // Nothing to clean up (matches Rust implementation)
    }

    // MARK: - Remote Service Implementation

    // Remote services in Rust don't register actions - they're just proxies
    // This implementation follows the same pattern for alignment
}