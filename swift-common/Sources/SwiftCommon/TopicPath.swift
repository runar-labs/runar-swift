/// The types of segments that can appear in a TopicPath
public enum PathSegment: Equatable, Hashable, Sendable {
    /// A literal string segment (e.g., "services", "auth", "login").
    /// Literal segments must match exactly for a path to be considered a match.
    case literal(String)

    /// A template parameter segment (e.g., "{service_path}", "{user_id}").
    /// Template parameters match any segment and store the matched value for later use.
    /// The parameter name is stored without the braces for easier access.
    case template(String)

    /// A single-segment wildcard (`*`) - matches any single segment.
    /// Single wildcards match exactly one path segment.
    case singleWildcard

    /// A multi-segment wildcard (`>`) - matches one or more segments to the end.
    /// Multi wildcards match one or more path segments from their position to the
    /// end of the path. They must be the last segment in a pattern.
    case multiWildcard

    /// Parse a string segment into a PathSegment
    public static func from(_ segment: String) -> Self {
        switch segment {
        case "*": return .singleWildcard
        case ">": return .multiWildcard
        default:
            if segment.hasPrefix("{"), segment.hasSuffix("}") {
                // Template parameter - extract the parameter name without braces
                let paramName = String(segment.dropFirst().dropLast())
                return .template(paramName)
            } else {
                return .literal(segment)
            }
        }
    }

    /// Convert back to string representation
    public func asString() -> String {
        switch self {
        case let .literal(value): value
        case let .template(param): "{\(param)}"
        case .singleWildcard: "*"
        case .multiWildcard: ">"
        }
    }

    /// Check if this segment is a wildcard
    public var isWildcard: Bool {
        switch self {
        case .singleWildcard, .multiWildcard: true
        case .literal, .template: false
        }
    }

    /// Check if this segment is a template parameter
    public var isTemplate: Bool {
        switch self {
        case .template: true
        case .literal, .singleWildcard, .multiWildcard: false
        }
    }
}

/// TopicPath: highly optimized path with network id and segments
public struct TopicPath: Equatable, Hashable, Sendable {
    /// The raw path string with validated format
    public let rawPath: String

    /// The network ID for this path
    public let networkId: String

    /// The segments after the network ID
    public let segments: [PathSegment]

    /// Whether this path contains wildcard patterns
    public let isPattern: Bool

    /// Whether this path contains template parameters
    public let hasTemplates: Bool

    /// The service name (first segment of the path) - cached for convenience
    public let servicePath: String

    /// Cached action path (all segments joined) - computed once at creation time
    public let actionPath: String

    /// Segment count - cached for quick filtering
    public let segmentCount: Int

    /// Pre-computed hash components for faster hashing
    private let hashComponents: [UInt64]

    /// Bitmap representation of segment types for fast pattern matching
    /// Each 2 bits represent a segment type:
    /// - 00: Literal
    /// - 01: Template
    /// - 10: SingleWildcard
    /// - 11: MultiWildcard
    private let segmentTypeBitmap: UInt64

    /// Helper struct for segment parsing results
    private struct SegmentParseResult {
        let segments: [PathSegment]
        let hasPattern: Bool
        let hasTemplates: Bool
        let bitmap: UInt64
    }

    /// Helper method to parse and validate segments
    private static func parseAndValidateSegments(_ segments: [String]) throws -> SegmentParseResult {
        var parsedSegments: [PathSegment] = []
        var hasPattern = false
        var hasTemplateParams = false
        var segmentTypeBits: [UInt64] = []

        for (index, segment) in segments.enumerated() {
            let pathSegment = PathSegment.from(segment)
            parsedSegments.append(pathSegment)

            // Validate multi-wildcard position
            if case .multiWildcard = pathSegment {
                if index != segments.count - 1 {
                    throw TopicPathError.invalidMultiWildcard("Multi-wildcard (>) must be the last segment")
                }
            }

            // Update flags
            if pathSegment.isWildcard {
                hasPattern = true
            }
            if pathSegment.isTemplate {
                hasTemplateParams = true
            }

            // Add to bitmap (2 bits per segment)
            let typeBits: UInt64 = switch pathSegment {
            case .literal: 0b00
            case .template: 0b01
            case .singleWildcard: 0b10
            case .multiWildcard: 0b11
            }
            segmentTypeBits.append(typeBits)
        }

        // Build segment type bitmap
        var bitmap: UInt64 = 0
        for (index, bits) in segmentTypeBits.enumerated() where index < 32 {
            // Only 64 bits available, so max 32 segments
            bitmap |= bits << (index * 2)
        }

        return SegmentParseResult(
            segments: parsedSegments,
            hasPattern: hasPattern,
            hasTemplates: hasTemplateParams,
            bitmap: bitmap
        )
    }

    /// Primary constructor matching Rust API: TopicPath::new(path, default_network)
    public static func new(_ path: String, defaultNetwork: String) throws -> TopicPath {
        // Validate defaultNetwork parameter
        guard !defaultNetwork.isEmpty else {
            throw TopicPathError.invalidNetworkId("Network ID cannot be empty")
        }

        // Parse the network ID and path parts (matching Rust logic exactly)
        let (actualNetworkId, pathWithoutNetwork): (String, String)
        if path.contains(":") {
            // Split at the first colon to separate network_id and path
            let parts = path.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if parts.count != 2 {
                throw TopicPathError.invalidPath("Invalid path format - should be 'network_id:service_path' or 'service_path': \(path)")
            }

            // Reject empty network IDs
            if parts[0].isEmpty {
                throw TopicPathError.invalidNetworkId("Network ID cannot be empty: \(path)")
            }

            actualNetworkId = parts[0]
            pathWithoutNetwork = parts[1]
        } else {
            // No network_id prefix, use the default
            actualNetworkId = defaultNetwork
            pathWithoutNetwork = path
        }

        // Split the path into segments (matching Rust logic)
        let pathSegments = pathWithoutNetwork
            .split(separator: "/")
            .filter { !$0.isEmpty }
            .map(String.init)

        // Paths must have at least one segment (the service name)
        guard !pathSegments.isEmpty else {
            throw TopicPathError.invalidPath("Invalid path - must have at least one segment: \(path)")
        }

        // Parse and validate segments
        let result = try Self.parseAndValidateSegments(pathSegments)
        let parsedSegments = result.segments
        let hasPattern = result.hasPattern
        let hasTemplateParams = result.hasTemplates
        let bitmap = result.bitmap

        // Extract paths
        let serviceSegment = parsedSegments[0].asString()
        let actionPathStr = parsedSegments.count <= 1 ? "" : parsedSegments.map { $0.asString() }.joined(separator: "/")

        // Build raw path
        let rawPathStr = "\(actualNetworkId):\(pathSegments.joined(separator: "/"))"

        // Pre-compute hash components
        var hashComps: [UInt64] = []
        hashComps.append(UInt64(bitPattern: Int64(actualNetworkId.hashValue)))
        for segment in parsedSegments {
            hashComps.append(UInt64(bitPattern: Int64(segment.asString().hashValue)))
        }

        return TopicPath(
            rawPath: rawPathStr,
            networkId: actualNetworkId,
            segments: parsedSegments,
            isPattern: hasPattern,
            hasTemplates: hasTemplateParams,
            servicePath: serviceSegment,
            actionPath: actionPathStr,
            segmentCount: parsedSegments.count,
            hashComponents: hashComps,
            segmentTypeBitmap: bitmap
        )
    }

    /// Internal constructor for creating TopicPath instances
    private init(
        rawPath: String,
        networkId: String,
        segments: [PathSegment],
        isPattern: Bool,
        hasTemplates: Bool,
        servicePath: String,
        actionPath: String,
        segmentCount: Int,
        hashComponents: [UInt64],
        segmentTypeBitmap: UInt64
    ) {
        self.rawPath = rawPath
        self.networkId = networkId
        self.segments = segments
        self.isPattern = isPattern
        self.hasTemplates = hasTemplates
        self.servicePath = servicePath
        self.actionPath = actionPath
        self.segmentCount = segmentCount
        self.hashComponents = hashComponents
        self.segmentTypeBitmap = segmentTypeBitmap
    }

    /// Create a TopicPath from a full path string (matches Rust from_full_path)
    public static func fromFullPath(_ path: String) throws -> TopicPath {
        if path.contains(":") {
            // Split on ALL colons to separate network_id and path (matching Rust exactly)
            let parts = path.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            if parts.count != 2 {
                throw TopicPathError.invalidPath("Invalid path format - should be 'network_id:service_path' received: \(path)")
            }

            // Reject empty network IDs
            if parts[0].isEmpty {
                throw TopicPathError.invalidNetworkId("Invalid path format - network ID cannot be empty received: \(path)")
            }

            let networkId = parts[0]
            let pathPart = parts[1]

            guard !pathPart.isEmpty else {
                throw TopicPathError.invalidPath("Path part cannot be empty")
            }

            return try TopicPath.new(pathPart, defaultNetwork: networkId)
        } else {
            // No network_id prefix - this is an error in Rust
            throw TopicPathError.invalidPath("Invalid path format - missing network_id received: \(path)")
        }
    }

    /// Create a service-only TopicPath (matches Rust new_service exactly)
    public static func newService(_ networkId: String, serviceName: String) -> TopicPath {
        // This matches Rust implementation exactly - no throws, direct construction
        let path = "\(networkId):\(serviceName)"

        // Parse segments (single service name)
        let segments = [PathSegment.literal(serviceName)]

        // Pre-compute hash components
        var hashComps: [UInt64] = []
        hashComps.append(UInt64(bitPattern: Int64(networkId.hashValue)))
        hashComps.append(UInt64(bitPattern: Int64(serviceName.hashValue)))

        return TopicPath(
            rawPath: path,
            networkId: networkId,
            segments: segments,
            isPattern: false,
            hasTemplates: false,
            servicePath: serviceName,
            actionPath: "",
            segmentCount: 1,
            hashComponents: hashComps,
            segmentTypeBitmap: 0b00 // Single literal segment
        )
    }

    /// Create an action TopicPath from a service path
    public func newActionTopic(_ action: String) throws -> TopicPath {
        guard !action.contains("/") else {
            throw TopicPathError.invalidActionName("Action name cannot contain '/'")
        }
        guard !action.contains(":") else {
            throw TopicPathError.invalidActionName("Action name cannot contain ':'")
        }

        // Cannot create action from path that already has action (more than 1 segment)
        guard segments.count == 1 else {
            throw TopicPathError.invalidChildOfMultiWildcard(
                "cannot create an action path on top of another action path"
            )
        }

        let newSegments = segments.map { $0.asString() } + [action]
        let path = newSegments.joined(separator: "/")
        return try TopicPath.new(path, defaultNetwork: networkId)
    }

    /// Create an event TopicPath from a service path
    public func newEventTopic(_ event: String) throws -> TopicPath {
        guard !event.contains("/") else {
            throw TopicPathError.invalidEventName("Event name cannot contain '/'")
        }
        let newSegments = segments.map { $0.asString() } + [event]
        let path = newSegments.joined(separator: "/")
        return try TopicPath.new(path, defaultNetwork: networkId)
    }

    /// Get the parent path (one level up)
    public func parent() throws -> TopicPath? {
        guard segmentCount > 1 else { return nil }

        let parentSegments = segments.dropLast().map { $0.asString() }
        let path = parentSegments.joined(separator: "/")
        return try TopicPath.new(path, defaultNetwork: networkId)
    }

    /// Create a child path by adding a segment
    public func child(_ segment: String) throws -> TopicPath {
        guard !segment.contains("/") else {
            throw TopicPathError.invalidSegment("Segment cannot contain '/'")
        }

        // Check if current path ends with multi-wildcard
        if let lastSegment = segments.last, case .multiWildcard = lastSegment {
            throw TopicPathError.invalidChildOfMultiWildcard("Cannot add child to path ending with multi-wildcard")
        }

        let newSegments = segments.map { $0.asString() } + [segment]
        let path = newSegments.joined(separator: "/")
        return try TopicPath.new(path, defaultNetwork: networkId)
    }

    /// Check if this path starts with another path
    public func startsWith(_ other: TopicPath) -> Bool {
        guard networkId == other.networkId else { return false }
        guard segmentCount >= other.segmentCount else { return false }

        for (index, otherSegment) in other.segments.enumerated() {
            let thisSegment = segments[index]
            switch (thisSegment, otherSegment) {
            case let (.literal(this), .literal(other)):
                if this != other { return false }
            case (.template, .template):
                // Template matches template
                break
            case (.singleWildcard, .singleWildcard), (.multiWildcard, .multiWildcard):
                // Wildcard matches wildcard
                break
            default:
                return false
            }
        }

        return true
    }

    /// Check if this path matches a template pattern
    public func matchesTemplate(_ template: String) -> Bool {
        do {
            let templatePath = try TopicPath.fromFullPath("\(networkId):\(template)")

            // Must have same number of segments
            guard segmentCount == templatePath.segmentCount else { return false }

            // Check each segment for template matching
            for (thisSegment, templateSegment) in zip(segments, templatePath.segments) {
                switch (thisSegment, templateSegment) {
                case let (.literal(this), .literal(template)):
                    // Literals must match exactly
                    if this != template { return false }
                case (.literal, .template):
                    // Concrete literal matches template parameter
                    continue
                case (.template, .template):
                    // Both are templates - match
                    continue
                default:
                    // Any other combination doesn't match
                    return false
                }
            }

            return true
        } catch {
            return false
        }
    }

    /// Extract parameters from a path that matches a template
    public func extractParams(_ template: String) -> [String: String]? {
        do {
            let templatePath = try TopicPath.fromFullPath("\(networkId):\(template)")

            guard segmentCount == templatePath.segmentCount else { return nil }

            var params: [String: String] = [:]

            for (thisSegment, templateSegment) in zip(segments, templatePath.segments) {
                switch (thisSegment, templateSegment) {
                case let (.literal(this), .literal(template)):
                    if this != template { return nil }
                case let (.literal(value), .template(paramName)):
                    params[paramName] = value
                case (.template, .template):
                    // Template matches template - no parameter extraction
                    break
                default:
                    return nil
                }
            }

            return params
        } catch {
            return nil
        }
    }

    /// Create a path from a template with parameters
    public static func fromTemplate(_ template: String,
                                    params: [String: String],
                                    networkId: String) throws -> TopicPath
    {
        let segments = template.split(separator: "/").map(String.init)
        var resolvedSegments: [String] = []

        for segment in segments {
            if segment.hasPrefix("{"), segment.hasSuffix("}") {
                let paramName = String(segment.dropFirst().dropLast())
                guard let paramValue = params[paramName] else {
                    throw TopicPathError.missingTemplateParameter("Missing parameter: \(paramName)")
                }
                resolvedSegments.append(paramValue)
            } else {
                resolvedSegments.append(segment)
            }
        }

        let path = resolvedSegments.joined(separator: "/")
        return try TopicPath.new(path, defaultNetwork: networkId)
    }

    /// Check if this path matches another path (handles wildcards and templates)
    public func matches(_ other: TopicPath) -> Bool {
        guard networkId == other.networkId else { return false }

        // Handle patterns with multi-wildcards
        return matchesSegments(segments, patternIndex: 0, pathIndex: 0,
                               pathSegments: other.segments)
    }

    private func matchesSegments(_ patternSegments: [PathSegment],
                                 patternIndex: Int,
                                 pathIndex: Int,
                                 pathSegments: [PathSegment]? = nil) -> Bool
    {
        let actualPathSegments = pathSegments ?? segments

        // If we've consumed both pattern and path, we have a match
        if patternIndex == patternSegments.count, pathIndex == actualPathSegments.count {
            return true
        }

        // If we've consumed the pattern but not the path, no match
        if patternIndex == patternSegments.count {
            return false
        }

        let patternSegment = patternSegments[patternIndex]

        switch patternSegment {
        case .singleWildcard:
            // Single wildcard matches exactly one segment
            if pathIndex < actualPathSegments.count {
                // Continue matching the rest
                return matchesSegments(patternSegments, patternIndex: patternIndex + 1,
                                       pathIndex: pathIndex + 1, pathSegments: actualPathSegments)
            } else {
                return false
            }

        case .multiWildcard:
            // Multi-wildcard matches zero or more segments
            // If this is the last pattern segment, it matches everything remaining
            if patternIndex == patternSegments.count - 1 {
                return true
            }

            // Otherwise, try all possible positions for where the rest of the pattern should match
            for nextPathIndex in pathIndex ... actualPathSegments.count where
                matchesSegments(patternSegments, patternIndex: patternIndex + 1,
                                pathIndex: nextPathIndex, pathSegments: actualPathSegments)
            {
                return true
            }
            return false

        default:
            // If we're past the end of the path but still have pattern segments, no match
            if pathIndex == actualPathSegments.count {
                return false
            }

            let pathSegment = actualPathSegments[pathIndex]

            // For regular matches(), we use strict matching where only identical segments match
            // Template segments should not match literal segments in this direction
            if pathSegment == patternSegment {
                // Continue matching the rest
                return matchesSegments(patternSegments, patternIndex: patternIndex + 1,
                                       pathIndex: pathIndex + 1, pathSegments: actualPathSegments)
            } else {
                return false
            }
        }
    }

    /// Get the string representation
    public func asString() -> String {
        rawPath
    }

    /// Custom hash implementation using pre-computed components
    public func hash(into hasher: inout Hasher) {
        for component in hashComponents {
            hasher.combine(component)
        }
    }

    /// Custom equality implementation
    public static func == (lhs: TopicPath, rhs: TopicPath) -> Bool {
        guard lhs.networkId == rhs.networkId else { return false }
        guard lhs.segmentCount == rhs.segmentCount else { return false }

        for (left, right) in zip(lhs.segments, rhs.segments) where left != right {
            return false
        }

        return true
    }
}

/// Helper extension for PathSegment matching
private extension PathSegment {
    func matchesSegment(_ other: PathSegment) -> Bool {
        // Handle literal cases first
        if case let (.literal(this), .literal(other)) = (self, other) {
            return this == other
        }

        // Use type-based matching to reduce complexity
        return matchesByType(other)
    }

    private func matchesByType(_ other: PathSegment) -> Bool {
        switch self {
        case .literal:
            false // Literal can only match identical literal
        case .template:
            other.isLiteral || other.isTemplate
        case .singleWildcard:
            other.isLiteral || other.isTemplate || other.isSingleWildcard
        case .multiWildcard:
            other.isLiteral || other.isTemplate || other.isMultiWildcard
        }
    }

    private var isLiteral: Bool {
        if case .literal = self { return true }
        return false
    }

    private var isSingleWildcard: Bool {
        if case .singleWildcard = self { return true }
        return false
    }

    private var isMultiWildcard: Bool {
        if case .multiWildcard = self { return true }
        return false
    }
}

/// Errors that can occur when working with TopicPath
public enum TopicPathError: Error, Equatable {
    case invalidNetworkId(String)
    case invalidPath(String)
    case invalidMultiWildcard(String)
    case invalidActionName(String)
    case invalidEventName(String)
    case invalidSegment(String)
    case invalidChildOfMultiWildcard(String)
    case missingTemplateParameter(String)
}
