import Foundation
import RunarSerializer
import SwiftCommon

public struct LifecycleContext {
    public let networkId: String
    public let servicePath: String
    public let config: AnyValue?
    public let logger: RunarLogger
    public let nodeDelegate: NodeDelegate

    public init(networkId: String, servicePath: String, config: AnyValue?, logger: RunarLogger, nodeDelegate: NodeDelegate) {
        self.networkId = networkId
        self.servicePath = servicePath
        self.config = config
        self.logger = logger
        self.nodeDelegate = nodeDelegate
    }

    public func registerAction(_ action: String, handler: @escaping ActionHandler) async throws {
        try await nodeDelegate.registerAction(networkId: networkId, servicePath: servicePath, action: action, handler: handler)
    }

    public func subscribe(_ topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String {
        try await nodeDelegate.subscribe(topic: qualify(topic), options: options, callback: callback)
    }

    public func publish(_ topic: String, data: AnyValue?) async throws {
        try await nodeDelegate.publish(topic: qualify(topic), data: data)
    }

    private func qualify(_ pathOrTopic: String) -> String {
        if pathOrTopic.contains(":") { return pathOrTopic }
        if pathOrTopic.contains("/") { return "\(networkId):\(pathOrTopic)" }
        return "\(networkId):\(servicePath)/\(pathOrTopic)"
    }
}

public struct RequestContext {
    public let networkId: String
    public let servicePath: String
    public let logger: RunarLogger
    public let nodeDelegate: NodeDelegate
    public var pathParams: [String: String]
    public let userProfilePublicKey: Data
}

public struct EventContext {
    public let topic: String
    public let logger: RunarLogger
    public let nodeDelegate: NodeDelegate
    public let isLocal: Bool
}
