import Foundation

// MARK: - Error Types

public protocol RunarError: Error, CustomStringConvertible {
    var code: String { get }
    var message: String { get }
    var component: Component { get }
    var context: ErrorContext { get }
}

/// Error context for additional debugging information
public struct ErrorContext: Sendable {
    public var nodeId: String?
    public var servicePath: String?
    public var actionPath: String?
    public var peerId: String?
    public var additionalInfo: [String: String]

    public init(
        nodeId: String? = nil,
        servicePath: String? = nil,
        actionPath: String? = nil,
        peerId: String? = nil,
        additionalInfo: [String: String] = [:]
    ) {
        self.nodeId = nodeId
        self.servicePath = servicePath
        self.actionPath = actionPath
        self.peerId = peerId
        self.additionalInfo = additionalInfo
    }
}

/// Base implementation of RunarError
public struct BaseRunarError: RunarError {
    public let code: String
    public let message: String
    public let component: Component
    public let context: ErrorContext
    public let underlying: Error?

    public init(
        code: String,
        message: String,
        component: Component,
        context: ErrorContext = ErrorContext(),
        underlying: Error? = nil
    ) {
        self.code = code
        self.message = message
        self.component = component
        self.context = context
        self.underlying = underlying
    }

    public var description: String {
        var parts = ["[\(component.displayName)] \(code): \(message)"]

        if let nodeId = context.nodeId {
            parts.append("node=\(nodeId)")
        }
        if let servicePath = context.servicePath {
            parts.append("service=\(servicePath)")
        }
        if let actionPath = context.actionPath {
            parts.append("action=\(actionPath)")
        }
        if let peerId = context.peerId {
            parts.append("peer=\(peerId)")
        }

        for (key, value) in context.additionalInfo {
            parts.append("\(key)=\(value)")
        }

        return parts.joined(separator: " ")
    }
}

// MARK: - Standard Error Types

public extension BaseRunarError {
    /// Network-related errors
    static func networkError(_ message: String, component: Component, context: ErrorContext = ErrorContext()) -> BaseRunarError {
        BaseRunarError(code: "NETWORK_ERROR", message: message, component: component, context: context)
    }

    /// Service-related errors
    static func serviceError(_ message: String, component: Component, context: ErrorContext = ErrorContext()) -> BaseRunarError {
        BaseRunarError(code: "SERVICE_ERROR", message: message, component: component, context: context)
    }

    /// Service not found errors
    static func serviceNotFound(servicePath: String, component: Component = .registry, context: ErrorContext = ErrorContext()) -> BaseRunarError {
        BaseRunarError.serviceError("Service not found", component: component, context: ErrorContext(
            servicePath: servicePath,
            additionalInfo: context.additionalInfo
        ))
    }

    /// Peer unavailable errors
    static func peerUnavailable(peerId: String, component: Component = .transporter, context: ErrorContext = ErrorContext()) -> BaseRunarError {
        BaseRunarError.networkError("Peer unavailable", component: component, context: ErrorContext(
            peerId: peerId,
            additionalInfo: context.additionalInfo
        ))
    }

    /// Registry-related errors
    static func registryError(_ message: String, component: Component, context: ErrorContext = ErrorContext()) -> BaseRunarError {
        BaseRunarError(code: "REGISTRY_ERROR", message: message, component: component, context: context)
    }

    /// Serialization errors
    static func serializationError(_ message: String, component: Component, context: ErrorContext = ErrorContext()) -> BaseRunarError {
        BaseRunarError(code: "SERIALIZATION_ERROR", message: message, component: component, context: context)
    }

    /// Authentication/authorization errors
    static func authError(_ message: String, component: Component, context: ErrorContext = ErrorContext()) -> BaseRunarError {
        BaseRunarError(code: "AUTH_ERROR", message: message, component: component, context: context)
    }

    /// Configuration errors
    static func configError(_ message: String, component: Component, context: ErrorContext = ErrorContext()) -> BaseRunarError {
        BaseRunarError(code: "CONFIG_ERROR", message: message, component: component, context: context)
    }
}

// MARK: - Error Utilities

/// Error handling utilities matching Rust patterns
public enum ErrorUtil {
    /// Create a contextual error with additional information
    public static func withContext(
        _ error: some Error,
        component: Component,
        context: ErrorContext
    ) -> BaseRunarError {
        if let runarError = error as? BaseRunarError {
            return BaseRunarError(
                code: runarError.code,
                message: runarError.message,
                component: component,
                context: context,
                underlying: runarError.underlying ?? error
            )
        } else {
            return BaseRunarError(
                code: "GENERIC_ERROR",
                message: error.localizedDescription,
                component: component,
                context: context,
                underlying: error
            )
        }
    }

    /// Chain errors while preserving context
    public static func chain(
        _ error: some Error,
        code: String,
        message: String,
        component: Component,
        context: ErrorContext = ErrorContext()
    ) -> BaseRunarError {
        BaseRunarError(
            code: code,
            message: message,
            component: component,
            context: context,
            underlying: error
        )
    }

    /// Create a service-specific error with path context
    public static func serviceNotFound(
        servicePath: String,
        nodeId: String? = nil,
        component: Component = .registry
    ) -> BaseRunarError {
        BaseRunarError.serviceError(
            "Service not found",
            component: component,
            context: ErrorContext(
                nodeId: nodeId,
                servicePath: servicePath
            )
        )
    }

    /// Create an action-specific error with path context
    public static func actionNotFound(
        actionPath: String,
        servicePath: String? = nil,
        nodeId: String? = nil,
        component: Component = .registry
    ) -> BaseRunarError {
        BaseRunarError.serviceError(
            "Action not found",
            component: component,
            context: ErrorContext(
                nodeId: nodeId,
                servicePath: servicePath,
                actionPath: actionPath
            )
        )
    }

    /// Create a network-specific error with peer context
    public static func peerUnavailable(
        peerId: String,
        nodeId: String? = nil,
        component: Component = .transporter
    ) -> BaseRunarError {
        BaseRunarError.networkError(
            "Peer unavailable",
            component: component,
            context: ErrorContext(
                nodeId: nodeId,
                peerId: peerId
            )
        )
    }
}
