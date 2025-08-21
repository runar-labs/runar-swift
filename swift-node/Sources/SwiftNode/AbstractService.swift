import Foundation
import SwiftCommon
import RunarSerializer

public enum ServiceState: String, Codable, Sendable {
	case created
	case initializing
	case initialized
	case starting
	case running
	case pausing
	case paused
	case stopping
	case stopped
	case error
	case unknown

	public var isActive: Bool {
		switch self {
		case .running, .pausing, .paused:
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

	func initService(_ context: LifecycleContext) async throws
	func start(_ context: LifecycleContext) async throws
	func pause(_ context: LifecycleContext) async throws
	func resume(_ context: LifecycleContext) async throws
	func stop(_ context: LifecycleContext) async throws
	func handleError(_ error: Error, context: LifecycleContext) async
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
			try await performInit(context)
			await transition(to: .initialized)
			logger.info("Service \(name) initialized successfully")
		} catch {
			await transition(to: .error)
			await handleError(error, context: context)
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
			await handleError(error, context: context)
			throw error
		}
	}

	public func pause(_ context: LifecycleContext) async throws {
		await transition(to: .pausing)
		do {
			try await performPause(context)
			await transition(to: .paused)
			logger.info("Service \(name) paused successfully")
		} catch {
			await transition(to: .error)
			await handleError(error, context: context)
			throw error
		}
	}

	public func resume(_ context: LifecycleContext) async throws {
		guard state == .paused else {
			throw BaseRunarError.serviceError("Service is not paused", component: .service)
		}

		await transition(to: .starting)
		do {
			try await performResume(context)
			await transition(to: .running)
			logger.info("Service \(name) resumed successfully")
		} catch {
			await transition(to: .error)
			await handleError(error, context: context)
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
			await handleError(error, context: context)
			throw error
		}
	}

	public func handleError(_ error: Error, context: LifecycleContext) async {
		logger.error("Service \(name) error: \(error.localizedDescription)")

		// Log error with context
		let errorContext = ErrorContext(
			nodeId: context.nodeId,
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
	open func performInit(_ context: LifecycleContext) async throws {
		// Default implementation does nothing
	}

	/// Override in subclasses to implement custom start logic
	open func performStart(_ context: LifecycleContext) async throws {
		// Default implementation does nothing
	}

	/// Override in subclasses to implement custom pause logic
	open func performPause(_ context: LifecycleContext) async throws {
		// Default implementation does nothing
	}

	/// Override in subclasses to implement custom resume logic
	open func performResume(_ context: LifecycleContext) async throws {
		// Default implementation does nothing
	}

	/// Override in subclasses to implement custom stop logic
	open func performStop(_ context: LifecycleContext) async throws {
		// Default implementation does nothing
	}
}

// MARK: - Lifecycle Context

public struct LifecycleContext {
	public let networkId: String
	public let servicePath: String
	public let config: AnyValue?
	public let logger: RunarLogger
	public let nodeDelegate: NodeDelegate
	public let nodeId: String?

	public init(networkId: String, servicePath: String, config: AnyValue?, logger: RunarLogger, nodeDelegate: NodeDelegate, nodeId: String? = nil) {
		self.networkId = networkId
		self.servicePath = servicePath
		self.config = config
		self.logger = logger
		self.nodeDelegate = nodeDelegate
		self.nodeId = nodeId
	}

	public func registerAction(_ action: String, handler: @escaping ActionHandler) async throws {
		try await nodeDelegate.registerAction(
			networkId: networkId,
			servicePath: servicePath,
			action: action,
			handler: handler
		)
	}
}
