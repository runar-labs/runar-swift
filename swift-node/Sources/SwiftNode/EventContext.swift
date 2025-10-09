import Foundation
import SwiftCommon

/// Event context for event handlers
/// Matches Rust: EventContext struct
public struct EventContext: Sendable {
    /// Complete topic path for this event
    public let topicPath: TopicPath

    /// Logger instance specific to this context
    public let logger: RunarLogger

    /// Node delegate for making requests or publishing events
    public let nodeDelegate: NodeDelegate

    /// Delivery options used when publishing this event
    public let deliveryOptions: PublishOptions?

    /// Whether this event is local or remote
    public let isLocal: Bool

    /// Create a new EventContext with the given topic path and logger
    /// Matches Rust: EventContext::new()
    public init(
        topicPath: TopicPath,
        nodeDelegate: NodeDelegate,
        isLocal: Bool,
        logger: RunarLogger
    ) {
        self.topicPath = topicPath
        self.nodeDelegate = nodeDelegate
        self.isLocal = isLocal
        self.logger = logger.child(component: .custom("Event"))
        deliveryOptions = nil
    }

    /// Create a new EventContext with delivery options
    /// Matches Rust: EventContext::with_delivery_options()
    public init(
        topicPath: TopicPath,
        nodeDelegate: NodeDelegate,
        isLocal: Bool,
        logger: RunarLogger,
        deliveryOptions: PublishOptions?
    ) {
        self.topicPath = topicPath
        self.nodeDelegate = nodeDelegate
        self.isLocal = isLocal
        self.logger = logger.child(component: .custom("Event"))
        self.deliveryOptions = deliveryOptions
    }

    /// Add delivery options to an EventContext
    /// Matches Rust: EventContext::with_delivery_options()
    public func withDeliveryOptions(_ options: PublishOptions?) -> EventContext {
        EventContext(
            topicPath: topicPath,
            nodeDelegate: nodeDelegate,
            isLocal: isLocal,
            logger: logger,
            deliveryOptions: options
        )
    }

    /// Get the action path from the topic path
    /// Matches Rust: EventContext::action_path()
    public var actionPath: String {
        topicPath.actionPath
    }

    /// Check if this is a local event
    /// Matches Rust: EventContext::is_local()
    public var isLocalEvent: Bool {
        isLocal
    }
}
