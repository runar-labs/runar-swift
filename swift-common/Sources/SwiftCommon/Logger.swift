import Foundation
import os.log
import os

// MARK: - Error Handling (Matching Rust Implementation)

/// Base error type matching Rust's error handling patterns
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

// MARK: - Routing Module (Extracted from Swift-Node)

// TopicPath: normalized path with network id and segments
public struct TopicPath: Equatable, Hashable, Sendable {
    public let networkId: String
    public let segments: [String]
    public let isPattern: Bool

    public init(networkId: String, segments: [String]) {
        self.networkId = networkId
        self.segments = segments
        self.isPattern = segments.contains("*") || segments.contains(">") || segments.contains(where: { $0.hasPrefix("{") && $0.hasSuffix("}") })
    }

    public static func parse(_ full: String) -> TopicPath {
        let parts = full.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let net = parts.count > 1 ? parts[0] : "default"
        let rest = parts.count > 1 ? parts[1] : parts[0]
        let segs = rest.split(separator: "/").map(String.init)
        return TopicPath(networkId: net, segments: segs)
    }

    public func asString() -> String { "\(networkId):\(segments.joined(separator: "/"))" }
}

public struct PathTrieMatch<T> {
    public let content: T
    public let params: [String: String]
}

public final class PathTrie<T> {
    private var content: [T] = []
    private var children: [String: PathTrie<T>] = [:]
    private var wildcardChild: PathTrie<T>? // "*"
    private var templateChild: PathTrie<T>? // "{param}"
    private var templateParamName: String?
    private var multiWildcard: [T] = [] // for ">"
    private var networks: [String: PathTrie<T>] = [:]

    public init() {}

    public func setValue(topic: TopicPath, content value: T) {
        setValues(topic: topic, contents: [value])
    }

    public func setValues(topic: TopicPath, contents values: [T]) {
        let netTrie = networks[topic.networkId] ?? PathTrie<T>()
        networks[topic.networkId] = netTrie
        netTrie.setValuesInternal(segments: topic.segments, index: 0, contents: values)
    }

    public func appendValue(topic: TopicPath, content value: T) {
        let netTrie = networks[topic.networkId] ?? PathTrie<T>()
        networks[topic.networkId] = netTrie
        netTrie.appendValueInternal(segments: topic.segments, index: 0, content: value)
    }

    public func remove(where predicate: (T) -> Bool, topic: TopicPath) -> Bool {
        guard let netTrie = networks[topic.networkId] else { return false }
        return netTrie.removeInternal(segments: topic.segments, index: 0, predicate: predicate)
    }

    public func findMatches(topic: TopicPath) -> [PathTrieMatch<T>] {
        guard let netTrie = networks[topic.networkId] else { return [] }
        var results: [PathTrieMatch<T>] = []
        if topic.isPattern {
            netTrie.collectWildcardMatches(patternSegments: topic.segments, index: 0, results: &results)
            return results
        }
        netTrie.findMatchesInternal(segments: topic.segments, index: 0, results: &results, params: [:])
        return results
    }

    // MARK: internal
    private func setValuesInternal(segments: [String], index: Int, contents values: [T]) {
        guard index < segments.count else {
            content = values
            return
        }
        let seg = segments[index]
        if seg == ">" {
            multiWildcard.append(contentsOf: values)
            return
        } else if seg == "*" {
            if wildcardChild == nil { wildcardChild = PathTrie<T>() }
            wildcardChild?.setValuesInternal(segments: segments, index: index + 1, contents: values)
            return
        } else if seg.hasPrefix("{") && seg.hasSuffix("}") {
            if templateChild == nil { templateChild = PathTrie<T>(); templateParamName = String(seg.dropFirst().dropLast()) }
            templateChild?.setValuesInternal(segments: segments, index: index + 1, contents: values)
            return
        } else {
            let child = children[seg] ?? PathTrie<T>()
            children[seg] = child
            child.setValuesInternal(segments: segments, index: index + 1, contents: values)
        }
    }

    private func appendValueInternal(segments: [String], index: Int, content value: T) {
        guard index < segments.count else {
            content.append(value)
            return
        }
        let seg = segments[index]
        if seg == ">" {
            multiWildcard.append(value)
            return
        } else if seg == "*" {
            if wildcardChild == nil { wildcardChild = PathTrie<T>() }
            wildcardChild?.appendValueInternal(segments: segments, index: index + 1, content: value)
            return
        } else if seg.hasPrefix("{") && seg.hasSuffix("}") {
            if templateChild == nil { templateChild = PathTrie<T>(); templateParamName = String(seg.dropFirst().dropLast()) }
            templateChild?.appendValueInternal(segments: segments, index: index + 1, content: value)
            return
        } else {
            let child = children[seg] ?? PathTrie<T>()
            children[seg] = child
            child.appendValueInternal(segments: segments, index: index + 1, content: value)
        }
    }

    private func removeInternal(segments: [String], index: Int, predicate: (T) -> Bool) -> Bool {
        guard index < segments.count else {
            let original = content.count
            content.removeAll(where: predicate)
            return content.count != original
        }
        let seg = segments[index]
        if seg == ">" {
            let original = multiWildcard.count
            multiWildcard.removeAll(where: predicate)
            return multiWildcard.count != original
        } else if seg == "*" {
            return wildcardChild?.removeInternal(segments: segments, index: index + 1, predicate: predicate) ?? false
        } else if seg.hasPrefix("{") && seg.hasSuffix("}") {
            return templateChild?.removeInternal(segments: segments, index: index + 1, predicate: predicate) ?? false
        } else {
            return children[seg]?.removeInternal(segments: segments, index: index + 1, predicate: predicate) ?? false
        }
    }

    private func findMatchesInternal(segments: [String], index: Int, results: inout [PathTrieMatch<T>], params: [String: String]) {
        if index >= segments.count {
            for v in content { results.append(PathTrieMatch(content: v, params: params)) }
            for v in multiWildcard { results.append(PathTrieMatch(content: v, params: params)) }
            return
        }
        let seg = segments[index]
        // literal
        if let child = children[seg] {
            child.findMatchesInternal(segments: segments, index: index + 1, results: &results, params: params)
        }
        // template
        if let child = templateChild, let key = templateParamName {
            var next = params; next[key] = seg
            child.findMatchesInternal(segments: segments, index: index + 1, results: &results, params: next)
        }
        // wildcard
        if let child = wildcardChild {
            child.findMatchesInternal(segments: segments, index: index + 1, results: &results, params: params)
        }
        // multi wildcard at this level also applies
        for v in multiWildcard { results.append(PathTrieMatch(content: v, params: params)) }
    }

    private func collectWildcardMatches(patternSegments: [String], index: Int, results: inout [PathTrieMatch<T>]) {
        if index >= patternSegments.count {
            for v in content { results.append(PathTrieMatch(content: v, params: [:])) }
            for v in multiWildcard { results.append(PathTrieMatch(content: v, params: [:])) }
            collectAllHandlers(results: &results)
            return
        }
        let seg = patternSegments[index]
        if seg == "*" || seg == ">" {
            collectAllHandlers(results: &results)
            return
        }
        if let child = children[seg] {
            child.collectWildcardMatches(patternSegments: patternSegments, index: index + 1, results: &results)
        }
        if let child = wildcardChild {
            child.collectWildcardMatches(patternSegments: patternSegments, index: index + 1, results: &results)
        }
        if let child = templateChild {
            child.collectWildcardMatches(patternSegments: patternSegments, index: index + 1, results: &results)
        }
    }

    private func collectAllHandlers(results: inout [PathTrieMatch<T>]) {
        for v in content { results.append(PathTrieMatch(content: v, params: [:])) }
        for v in multiWildcard { results.append(PathTrieMatch(content: v, params: [:])) }
        for (_, c) in children { c.collectAllHandlers(results: &results) }
        wildcardChild?.collectAllHandlers(results: &results)
        templateChild?.collectAllHandlers(results: &results)
    }
}

// MARK: - Compact ID Generation (DNS-safe identifiers)

/// Compact ID generator that creates DNS-safe, URL-safe identifiers
/// Matches Rust's compact ID generation for node IDs and service identifiers
public final class CompactIdGenerator: Sendable {
    private static let charset = "0123456789abcdefghijklmnopqrstuvwxyz"
    private static let charsetCount = UInt8(charset.count)

    /// Generate a compact ID of specified length
    /// - Parameter length: Length of the ID (default: 20)
    /// - Returns: DNS-safe alphanumeric string
    public static func generate(length: Int = 20) -> String {
        var result = ""
        for _ in 0..<length {
            let randomIndex = UInt8.random(in: 0..<charsetCount)
            let character = charset[charset.index(charset.startIndex, offsetBy: Int(randomIndex))]
            result.append(character)
        }
        return result
    }

    /// Generate a compact ID with prefix
    /// - Parameters:
    ///   - prefix: Prefix to add (e.g., "node", "svc")
    ///   - length: Total length including prefix
    /// - Returns: Prefixed DNS-safe identifier
    public static func generateWithPrefix(_ prefix: String, totalLength: Int = 24) -> String {
        let idLength = totalLength - prefix.count - 1 // -1 for separator
        let id = generate(length: max(4, idLength))
        return "\(prefix)\(id)"
    }

    /// Validate if a string is a valid compact ID (DNS-safe alphanumeric)
    public static func isValidCompactId(_ id: String) -> Bool {
        guard !id.isEmpty else { return false }
        return id.allSatisfy { char in
            char.isASCII && (char.isLowercase || char.isNumber)
        }
    }
}

// MARK: - Cross-Platform Test Vectors Support

/// Support structures for cross-platform test vectors
/// These will be used by external test utilities to avoid cyclic dependencies
public enum SerializerTestVectorsSupport {
    /// Plain user struct matching Rust's PlainUser
    public struct PlainUser: Codable, Sendable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// Test profile struct matching Rust's TestProfile
    public struct TestProfile: Codable, Sendable {
        public let id: String
        public let secret: String

        public init(id: String, secret: String) {
            self.id = id
            self.secret = secret
        }
    }
}

// MARK: - Component-based Logging (Matching Rust Implementation)

/// Predefined components for logging categorization
/// Matches Rust's Component enum
public enum Component: String, Sendable {
    case node = "Node"
    case registry = "Registry"
    case service = "Service"
    case database = "DB"
    case transporter = "Network"
    case networkDiscovery = "NetworkDiscovery"
    case system = "System"
    case cli = "CLI"
    case keys = "Keys"
    case custom = "Custom"

    public var displayName: String {
        switch self {
        case .database: return "DB"
        case .transporter: return "Network"
        case .networkDiscovery: return "NetworkDiscovery"
        default: return rawValue
        }
    }
}

/// Log levels matching Rust's LogLevel
public enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    case critical = "CRIT"
}

/// Logging configuration
public struct LoggingConfig: Sendable {
    public var level: LogLevel
    public var enableConsole: Bool
    public var enableOSLog: Bool

    public init(level: LogLevel = .info, enableConsole: Bool = true, enableOSLog: Bool = true) {
        self.level = level
        self.enableConsole = enableConsole
        self.enableOSLog = enableOSLog
    }
}

/// Component-based logger matching Rust's Logger struct
@available(macOS 12.0, iOS 15.0, *)
public final class RunarLogger: Sendable {
    private let component: Component
    private let nodeId: String?
    private let parentComponent: Component?
    private let actionPath: String?
    private let eventPath: String?
    private let osLogger: OSLog
    private let config: LoggingConfig

    /// Create a new root logger for a specific component
    public init(component: Component, config: LoggingConfig = LoggingConfig()) {
        self.component = component
        self.nodeId = nil
        self.parentComponent = nil
        self.actionPath = nil
        self.eventPath = nil
        self.config = config

        let subsystem = "com.runar"
        let category = component.displayName
        self.osLogger = OSLog(subsystem: subsystem, category: category)
    }

    /// Create a root logger with node ID
    public init(component: Component, nodeId: String, config: LoggingConfig = LoggingConfig()) {
        self.component = component
        self.nodeId = nodeId
        self.parentComponent = nil
        self.actionPath = nil
        self.eventPath = nil
        self.config = config

        let subsystem = "com.runar"
        let category = component.displayName
        self.osLogger = OSLog(subsystem: subsystem, category: category)
    }

    /// Create a child logger with the same node ID but different component
    public func withComponent(_ component: Component) -> RunarLogger {
        RunarLogger(
            component: component,
            nodeId: nodeId,
            parentComponent: self.component,
            actionPath: actionPath,
            eventPath: eventPath,
            osLogger: osLogger,
            config: config
        )
    }

    /// Create a logger with an action path for request tracing
    public func withActionPath(_ path: String) -> RunarLogger {
        RunarLogger(
            component: component,
            nodeId: nodeId,
            parentComponent: parentComponent,
            actionPath: path,
            eventPath: eventPath,
            osLogger: osLogger,
            config: config
        )
    }

    /// Create a logger with an event path for event tracing
    public func withEventPath(_ path: String) -> RunarLogger {
        RunarLogger(
            component: component,
            nodeId: nodeId,
            parentComponent: parentComponent,
            actionPath: actionPath,
            eventPath: path,
            osLogger: osLogger,
            config: config
        )
    }

    private init(component: Component, nodeId: String?, parentComponent: Component?, actionPath: String?, eventPath: String?, osLogger: OSLog, config: LoggingConfig) {
        self.component = component
        self.nodeId = nodeId
        self.parentComponent = parentComponent
        self.actionPath = actionPath
        self.eventPath = eventPath
        self.osLogger = osLogger
        self.config = config
    }

    private func formatMessage(_ message: String) -> String {
        let timestamp = timestampString()
        let componentPath = formatComponentPath()
        let nodeInfo = nodeId.map { "|node=\($0)" } ?? ""
        let actionInfo = actionPath.map { "|action=\($0)" } ?? ""
        let eventInfo = eventPath.map { "|event=\($0)" } ?? ""

        return "[\(timestamp)]\(componentPath)\(nodeInfo)\(actionInfo)\(eventInfo) \(message)"
    }

    private func formatComponentPath() -> String {
        if let parent = parentComponent, parent != .node {
            return " [\(parent.displayName).\(component.displayName)]"
        } else {
            return " [\(component.displayName)]"
        }
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    private func shouldLog(_ level: LogLevel) -> Bool {
        let levels: [LogLevel] = [.debug, .info, .warning, .error, .critical]
        guard let currentIndex = levels.firstIndex(of: config.level),
              let messageIndex = levels.firstIndex(of: level) else {
            return false
        }
        return messageIndex >= currentIndex
    }

    // MARK: - Logging Methods

    public func debug(_ message: String) {
        guard shouldLog(.debug) else { return }
        let formattedMessage = formatMessage(message)

        if config.enableOSLog {
            os_log("%{public}@", log: osLogger, type: .debug, formattedMessage)
        }

        if config.enableConsole {
            print("[DEBUG] \(formattedMessage)")
        }
    }

    public func info(_ message: String) {
        guard shouldLog(.info) else { return }
        let formattedMessage = formatMessage(message)

        if config.enableOSLog {
            os_log("%{public}@", log: osLogger, type: .info, formattedMessage)
        }

        if config.enableConsole {
            print("[INFO] \(formattedMessage)")
        }
    }

    public func warning(_ message: String) {
        guard shouldLog(.warning) else { return }
        let formattedMessage = formatMessage(message)

        if config.enableOSLog {
            os_log("%{public}@", log: osLogger, type: .default, formattedMessage)
        }

        if config.enableConsole {
            print("[WARN] \(formattedMessage)")
        }
    }

    public func error(_ message: String) {
        guard shouldLog(.error) else { return }
        let formattedMessage = formatMessage(message)

        if config.enableOSLog {
            os_log("%{public}@", log: osLogger, type: .error, formattedMessage)
        }

        if config.enableConsole {
            print("[ERROR] \(formattedMessage)")
        }
    }

    public func critical(_ message: String) {
        guard shouldLog(.critical) else { return }
        let formattedMessage = formatMessage(message)

        if config.enableOSLog {
            os_log("%{public}@", log: osLogger, type: .fault, formattedMessage)
        }

        if config.enableConsole {
            print("[CRIT] \(formattedMessage)")
        }
    }
}

// MARK: - Backward Compatibility

/// Simple logger for backward compatibility during migration
@available(macOS 12.0, iOS 15.0, *)
public class SimpleRunarLogger {
    private let logger: RunarLogger

    public init(subsystem: String = "com.runar", category: String = "default") {
        let component: Component = category == "default" ? .system : .custom
        self.logger = RunarLogger(component: component)
    }

    public func debug(_ message: String) { logger.debug(message) }
    public func info(_ message: String) { logger.info(message) }
    public func warning(_ message: String) { logger.warning(message) }
    public func error(_ message: String) { logger.error(message) }
    public func critical(_ message: String) { logger.critical(message) }
}
