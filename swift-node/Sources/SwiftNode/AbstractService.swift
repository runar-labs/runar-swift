import Foundation
import RunarSerializer
import SwiftCommon

public enum ServiceState: String, Codable, Sendable {
    case created
    case initializing
    case initialized
    case starting
    case running
    case stopping
    case stopped
    case error
    case unknown

    public var isActive: Bool {
        switch self {
        case .running:
            return true
        default:
            return false
        }
    }

    public var canTransition: Bool {
        switch self {
        case .error, .unknown:
            return false
        default:
            return true
        }
    }
}

@MainActor
public protocol AbstractService: AnyObject {
    var name: String { get }
    var version: String { get }
    var path: String { get }
    var description: String { get }
    var networkId: String? { get set }
    var state: ServiceState { get }
    var logger: RunarLogger { get }

    /// Initialize the service (renamed from 'init' due to Swift reserved keyword)
    /// Note: This diverges from Rust's 'init' method name due to Swift language constraints
    func initService(_ context: LifecycleContext) async throws
    func start(_ context: LifecycleContext) async throws
    func stop(_ context: LifecycleContext) async throws
}

// MARK: - ServiceBase Implementation

@MainActor
open class ServiceBase: AbstractService {
    public let name: String
    public let version: String
    public let path: String
    public let description: String
    public let logger: RunarLogger

    public var networkId: String?
    public private(set) var state: ServiceState = .created

    private let stateQueue = DispatchQueue(label: "com.runar.service.state")
    private var stateObservers: [(ServiceState) -> Void] = []

    public init(name: String, version: String = "1.0.0", path: String, description: String, logger: RunarLogger) {
        self.name = name
        self.version = version
        self.path = path
        self.description = description
        self.logger = logger
    }

    // MARK: - State Management

    public func addStateObserver(_ observer: @escaping (ServiceState) -> Void) {
        stateQueue.sync {
            stateObservers.append(observer)
        }
    }

    private func transition(to newState: ServiceState) async {
        let oldState = state
        guard oldState.canTransition else {
            logger.warning("Cannot transition from \(oldState) to \(newState)")
            return
        }

        stateQueue.sync {
            state = newState
        }

        logger.info("Service \(name) state transition: \(oldState) -> \(newState)")

        // Notify observers
        let observers = stateQueue.sync { stateObservers }
        for observer in observers {
            observer(newState)
        }
    }

    // MARK: - Lifecycle Implementation

    public func initService(_ context: LifecycleContext) async throws {
        await transition(to: .initializing)
        do {
            try await performInitService(context)
            await transition(to: .initialized)
            logger.info("Service \(name) initialized successfully")
        } catch {
            await transition(to: .error)
            throw error
        }
    }

    public func start(_ context: LifecycleContext) async throws {
        await transition(to: .starting)
        do {
            try await performStart(context)
            await transition(to: .running)
            logger.info("Service \(name) started successfully")
        } catch {
            await transition(to: .error)
            throw error
        }
    }



    public func stop(_ context: LifecycleContext) async throws {
        await transition(to: .stopping)
        do {
            try await performStop(context)
            await transition(to: .stopped)
            logger.info("Service \(name) stopped successfully")
        } catch {
            await transition(to: .error)
            throw error
        }
    }

    public func handleError(_ error: Error, context: LifecycleContext) async {
        logger.error("Service \(name) error: \(error.localizedDescription)")

        // Log error with context
        let errorContext = ErrorContext(
            nodeId: context.networkId,
            servicePath: path,
            peerId: nil,
            additionalInfo: [
                "service_name": name,
                "service_version": version,
                "service_state": state.rawValue
            ]
        )

        let runarError = ErrorUtil.withContext(error, component: .service, context: errorContext)
        logger.error("Service error details: \(runarError.description)")
    }

    // MARK: - Template Methods

    /// Override in subclasses to implement custom initialization logic
    /// Called by initService() - use performStart() for startup logic
    open func performInitService(_: LifecycleContext) async throws {
        // Default implementation does nothing
    }

    /// Override in subclasses to implement custom start logic
    open func performStart(_: LifecycleContext) async throws {
        // Default implementation does nothing
    }

    /// Override in subclasses to implement custom stop logic
    open func performStop(_: LifecycleContext) async throws {
        // Default implementation does nothing
    }
}
