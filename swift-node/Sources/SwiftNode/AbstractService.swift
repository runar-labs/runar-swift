import Foundation
import RunarSerializer
import SwiftCommon

/// Represents the current lifecycle state of a service.
///
/// This enum tracks the lifecycle stage of a service to ensure proper
/// initialization and operational management. The state transitions
/// follow a predictable pattern: Created → Initialized → Running → Stopped.
///
/// # State Transitions
///
/// The service lifecycle follows this pattern:
/// - Created -> Initialized -> Running -> Stopped
/// - Error states can occur at any stage
///
/// # Examples
///
/// ```swift
/// // Check if a service is ready to handle requests
/// let serviceState = ServiceState.running
/// if serviceState == .running {
///     // Service is operational
/// }
///
/// // Check if a service needs to be started
/// let serviceState = ServiceState.initialized
/// if serviceState == .initialized {
///     // Service is ready to start
/// }
/// ```
public enum ServiceState: String, Codable, Sendable {
    /// Service is created but not initialized.
    ///
    /// This is the initial state after service creation. The service
    /// exists but hasn't been set up for operation yet.
    case created

    /// Service has been initialized and is ready to start.
    ///
    /// The service has completed its setup phase and registered
    /// its action handlers. It's ready to begin active operations.
    case initialized

    /// Service is running and actively handling requests.
    ///
    /// This is the normal operational state. The service is fully
    /// functional and can handle requests, publish events, and
    /// perform its intended operations.
    case running

    /// Service has been stopped and is no longer operational.
    ///
    /// The service has been gracefully shut down and has released
    /// all its resources. It cannot handle requests in this state.
    case stopped

    /// Service has been paused and is temporarily inactive.
    ///
    /// The service is in a suspended state where it maintains
    /// its resources but doesn't handle requests. It can be resumed.
    case paused

    /// Service has encountered an error and cannot operate.
    ///
    /// The service has failed during initialization, startup, or
    /// operation. It requires intervention to recover or restart.
    case error

    /// Service state is unknown or indeterminate.
    ///
    /// This state indicates that the service's current status
    /// cannot be determined. It may indicate a system issue.
    case unknown
}

/// Abstract service interface that all services must implement.
///
/// This protocol defines a common interface for all services, enabling uniform
/// management of service lifecycle and request handling. It establishes the
/// foundation for the service architecture and ensures consistent behavior
/// across all service implementations.
///
/// # Architectural Principles
///
/// - **Consistent Lifecycle**: All services follow the same init/start/stop pattern
/// - **Resource Management**: Proper resource allocation and cleanup
/// - **Predictable State**: Well-defined state transitions
/// - **Async Operations**: All lifecycle methods are asynchronous
/// - **Self-Describing**: Services provide metadata about their capabilities
///
/// # Lifecycle Methods
///
/// 1. **`initService`**: Set up the service for operation
/// 2. **`start`**: Begin active operations
/// 3. **`stop`**: Gracefully shut down the service
///
/// # Examples
///
/// ```swift
/// class MyService: AbstractService {
///     let name: String = "MyService"
///     let version: String = "1.0.0"
///     let path: String = "my-service"
///     let description: String = "My example service"
///     var networkId: String?
///     let logger: RunarLogger
///     
///     init(logger: RunarLogger) {
///         self.logger = logger
///     }
///
///     func initService(_ context: LifecycleContext) async throws {
///         // Register action handlers, set up connections, etc.
///     }
///
///     func start(_ context: LifecycleContext) async throws {
///         // Start background tasks, timers, etc.
///     }
///
///     func stop(_ context: LifecycleContext) async throws {
///         // Clean up resources, cancel tasks, etc.
///     }
/// }
/// ```
///
/// # Thread Safety
///
/// All services must be `@MainActor` to ensure they can be safely shared
/// across multiple threads and async tasks.
@MainActor
public protocol AbstractService: AnyObject {
    /// Get service name
    var name: String { get }

    /// Get service version
    var version: String { get }

    /// Get service path
    var path: String { get }

    /// Get service description
    var description: String { get }

    /// Get service network id
    var networkId: String? { get set }

    /// Set service network id
    func setNetworkId(_ networkId: String)

    /// Initialize the service
    ///
    /// INTENTION: Set up the service for operation, register handlers,
    /// establish connections to dependencies, and prepare internal state.
    ///
    /// This is where services should register their action handlers using
    /// the context's registration methods. The service should not perform
    /// any active operations during initialization.
    ///
    /// Initialization errors should be propagated to enable reporting and
    /// proper error handling.
    func initService(_ context: LifecycleContext) async throws

    /// Start the service
    ///
    /// INTENTION: Begin active operations after initialization is complete.
    /// This is where the service should start any background tasks, timers,
    /// or active processing activities.
    ///
    /// The service should be fully initialized before this method is called.
    func start(_ context: LifecycleContext) async throws

    /// Stop the service
    ///
    /// INTENTION: Gracefully terminate all active operations, cancel background
    /// tasks, and release resources. This method should ensure that the service
    /// can be cleanly shut down without data loss or corruption.
    func stop(_ context: LifecycleContext) async throws
}
