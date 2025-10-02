import Atomics
import Foundation
import os

// MARK: - Logging Types

public enum Component: Sendable, Equatable {
    case ffi
    case network
    case service
    case registry
    case transporter
    case serializer
    case node
    case custom(String)

    public var displayName: String {
        switch self {
        case .ffi: "ffi"
        case .network: "Network"
        case .service: "Service"
        case .registry: "Registry"
        case .transporter: "Transporter"
        case .serializer: "Serializer"
        case .node: "Node"
        case let .custom(customName): customName
        }
    }

    public var shouldShowInHierarchy: Bool {
        switch self {
        case .custom: true // Custom components should show their custom string values
        default: true
        }
    }
}

public enum LogLevel: String, Sendable, CaseIterable {
    case trace = "TRACE"
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"

    public var priority: Int {
        switch self {
        case .trace: 0
        case .debug: 1
        case .info: 2
        case .warning: 3
        case .error: 4
        }
    }
}

public struct LoggerConfig: Sendable {
    public let level: LogLevel
    public let includeTimestamp: Bool
    public let includeComponent: Bool
    public let includeContext: Bool

    public init(
        level: LogLevel = .info,
        includeTimestamp: Bool = true,
        includeComponent: Bool = true,
        includeContext: Bool = true
    ) {
        self.level = level
        self.includeTimestamp = includeTimestamp
        self.includeComponent = includeComponent
        self.includeContext = includeContext
    }
}

// MARK: - Global Configuration

public final class LoggerConfigManager: Sendable {
    public static let shared = LoggerConfigManager()
    static let globalConfigAtomic = ManagedAtomic<UInt64>(0)
    public var globalConfig: LoggerConfig {
        get {
            let atomicValue = Self.globalConfigAtomic.load(ordering: .relaxed)
            return Self.decodeConfig(from: atomicValue)
        }
        set {
            let atomicValue = Self.encodeConfig(newValue)
            Self.globalConfigAtomic.store(atomicValue, ordering: .relaxed)
        }
    }

    private init() {}

    // MARK: - Atomic Encoding/Decoding

    private static func encodeConfig(_ config: LoggerConfig) -> UInt64 {
        var value: UInt64 = 0

        // LogLevel (bits 0-2)
        value |= UInt64(config.level.priority) & 0x7

        // includeTimestamp (bit 3)
        if config.includeTimestamp {
            value |= 1 << 3
        }

        // includeComponent (bit 4)
        if config.includeComponent {
            value |= 1 << 4
        }

        // includeContext (bit 5)
        if config.includeContext {
            value |= 1 << 5
        }

        return value
    }

    static func decodeConfig(from atomicValue: UInt64) -> LoggerConfig {
        // LogLevel (bits 0-2)
        let levelOrdinal = Int(atomicValue & 0x7)
        let level = LogLevel.allCases.first { $0.priority == levelOrdinal } ?? .info

        // includeTimestamp (bit 3)
        let includeTimestamp = (atomicValue & (1 << 3)) != 0

        // includeComponent (bit 4)
        let includeComponent = (atomicValue & (1 << 4)) != 0

        // includeContext (bit 5)
        let includeContext = (atomicValue & (1 << 5)) != 0

        return LoggerConfig(
            level: level,
            includeTimestamp: includeTimestamp,
            includeComponent: includeComponent,
            includeContext: includeContext
        )
    }
}

// MARK: - Logger Implementation

public final class RunarLogger: Sendable {
    private let parent: RunarLogger?
    private let component: Component
    private let context: String?
    private let explicitConfig: LoggerConfig?

    // MARK: - Initialization

    private init(
        parent: RunarLogger? = nil,
        component: Component,
        context: String? = nil,
        config: LoggerConfig? = nil
    ) {
        self.parent = parent
        self.component = component
        self.context = context
        explicitConfig = config
    }

    // MARK: - Public Factory Methods

    public static func root(component: Component, context: String? = nil, config: LoggerConfig? = nil) -> RunarLogger {
        RunarLogger(parent: nil, component: component, context: context, config: config)
    }

    public func child(component: Component, context: String? = nil) -> RunarLogger {
        RunarLogger(parent: self, component: component, context: context, config: nil)
    }

    // MARK: - Logging Methods with @autoclosure

    public func trace(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        guard shouldLog(level: .trace) else { return }
        let evaluatedMessage = message() // Only evaluates if shouldLog() is true
        log(level: .trace, message: evaluatedMessage, file: file, line: line, function: function)
    }

    public func debug(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        guard shouldLog(level: .debug) else { return }
        let evaluatedMessage = message() // Only evaluates if shouldLog() is true
        log(level: .debug, message: evaluatedMessage, file: file, line: line, function: function)
    }

    public func info(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        guard shouldLog(level: .info) else { return }
        let evaluatedMessage = message() // Only evaluates if shouldLog() is true
        log(level: .info, message: evaluatedMessage, file: file, line: line, function: function)
    }

    public func warning(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        guard shouldLog(level: .warning) else { return }
        let evaluatedMessage = message() // Only evaluates if shouldLog() is true
        log(level: .warning, message: evaluatedMessage, file: file, line: line, function: function)
    }

    public func error(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        guard shouldLog(level: .error) else { return }
        let evaluatedMessage = message() // Only evaluates if shouldLog() is true
        log(level: .error, message: evaluatedMessage, file: file, line: line, function: function)
    }

    // MARK: - Private Implementation

    private func log(
        level: LogLevel,
        message: String,
        file _: String,
        line _: Int,
        function _: String
    ) {
        guard shouldLog(level: level) else { return }

        let formattedMessage = formatLogMessage(level: level, message: message)

        #if DEBUG
            print(formattedMessage)
        #else
            os_log("%{public}@", log: .default, type: .default, formattedMessage)
        #endif
    }

    private func shouldLog(level: LogLevel) -> Bool {
        let currentConfig = getCurrentConfig()
        return level.priority >= currentConfig.level.priority
    }

    private func getCurrentConfig() -> LoggerConfig {
        if let explicitConfig {
            return explicitConfig
        }

        // Read from atomic config for consistency
        let atomicValue = LoggerConfigManager.globalConfigAtomic.load(ordering: .relaxed)
        return LoggerConfigManager.decodeConfig(from: atomicValue)
    }

    private func formatLogMessage(level: LogLevel, message: String) -> String {
        let currentConfig = getCurrentConfig()
        var parts: [String] = []

        // Timestamp and Level together
        if currentConfig.includeTimestamp {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = formatter.string(from: Date())
            parts.append("[\(timestamp) \(level.rawValue)]")
        } else {
            parts.append("[\(level.rawValue)]")
        }

        // Component hierarchy and context
        if currentConfig.includeComponent || currentConfig.includeContext {
            let hierarchy = buildHierarchy()
            if !hierarchy.isEmpty {
                parts.append("[\(hierarchy)]")
            }
        }

        // Message
        parts.append(message)

        return parts.joined(separator: " ")
    }

    private func buildHierarchy() -> String {
        var components: [String] = []
        var contexts: [String] = []
        var current: RunarLogger? = self

        // Build hierarchy from current to root
        while let logger = current {
            // Only include components that should show in hierarchy
            if logger.component.shouldShowInHierarchy {
                components.insert(logger.component.displayName, at: 0)
            }
            if let context = logger.context {
                contexts.insert(context, at: 0)
            }
            current = logger.parent
        }

        // Combine components and contexts
        var result: [String] = []
        result.append(contentsOf: components)
        result.append(contentsOf: contexts)

        return result.joined(separator: " ")
    }
}
