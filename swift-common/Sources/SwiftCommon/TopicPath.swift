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
            if segment.hasPrefix("{") && segment.hasSuffix("}") {
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
        case .literal(let value): return value
        case .template(let param): return "{\(param)}"
        case .singleWildcard: return "*"
        case .multiWildcard: return ">"
        }
    }

    /// Check if this segment is a wildcard
    public var isWildcard: Bool {
        switch self {
        case .singleWildcard, .multiWildcard: return true
        case .literal, .template: return false
        }
    }

    /// Check if this segment is a template parameter
    public var isTemplate: Bool {
        switch self {
        case .template: return true
        case .literal, .singleWildcard, .multiWildcard: return false
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
            let typeBits: UInt64
            switch pathSegment {
            case .literal: typeBits = 0b00
            case .template: typeBits = 0b01
            case .singleWildcard: typeBits = 0b10
            case .multiWildcard: typeBits = 0b11
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

    public init(networkId: String = "default", segments: [String]) throws {
        // Validate inputs
        guard !networkId.isEmpty else {
            throw TopicPathError.invalidNetworkId("Network ID cannot be empty")
        }

        guard !segments.isEmpty else {
            throw TopicPathError.invalidPath("Path must have at least one segment")
        }

        // Parse and validate segments
        let result = try parseAndValidateSegments(segments)
        let parsedSegments = result.segments
        let hasPattern = result.hasPattern
        let hasTemplateParams = result.hasTemplates
        let bitmap = result.bitmap

        // Extract paths
        let serviceSegment = parsedSegments[0].asString()
        let actionPathStr = parsedSegments.count <= 1 ? "" : parsedSegments.map { $0.asString() }.joined(separator: "/")

        // Build raw path
        let rawPathStr = "\(networkId):\(segments.joined(separator: "/"))"

        // Pre-compute hash components
        var hashComps: [UInt64] = []
        hashComps.append(UInt64(bitPattern: Int64(networkId.hashValue)))
        for segment in parsedSegments {
            hashComps.append(UInt64(bitPattern: Int64(segment.asString().hashValue)))
        }

        self.rawPath = rawPathStr
        self.networkId = networkId
        self.segments = parsedSegments
        self.isPattern = hasPattern
        self.hasTemplates = hasTemplateParams
        self.servicePath = serviceSegment
        self.actionPath = actionPathStr
        self.segmentCount = parsedSegments.count
        self.hashComponents = hashComps
        self.segmentTypeBitmap = bitmap
    }

    /// Create a TopicPath from a full path string
    public static func parse(_ fullPath: String) throws -> TopicPath {
        let parts = fullPath.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let networkId = parts.count > 1 ? parts[0] : "default"
        let pathPart = parts.count > 1 ? parts[1] : parts[0]

        // Validate network ID doesn't contain multiple colons
        if fullPath.split(separator: ":").count > 2 {
            throw TopicPathError.invalidNetworkId("Network ID cannot contain ':' character")
        }

        guard !pathPart.isEmpty else {
            throw TopicPathError.invalidPath("Path part cannot be empty")
        }

        let segments = pathPart.split(separator: "/").map(String.init)
        return try TopicPath(networkId: networkId, segments: segments)
    }

    /// Create a service-only TopicPath
    public static func newService(_ networkId: String = "default", serviceName: String) throws -> TopicPath {
        return try TopicPath(networkId: networkId, segments: [serviceName])
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
        return try TopicPath(networkId: networkId, segments: newSegments)
    }

    /// Create an event TopicPath from a service path
    public func newEventTopic(_ event: String) throws -> TopicPath {
        guard !event.contains("/") else {
            throw TopicPathError.invalidEventName("Event name cannot contain '/'")
        }
        let newSegments = segments.map { $0.asString() } + [event]
        return try TopicPath(networkId: networkId, segments: newSegments)
    }

    /// Get the parent path (one level up)
    public func parent() throws -> TopicPath? {
        guard segmentCount > 1 else { return nil }

        let parentSegments = segments.dropLast().map { $0.asString() }
        return try TopicPath(networkId: networkId, segments: parentSegments)
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
        return try TopicPath(networkId: networkId, segments: newSegments)
    }

    /// Check if this path starts with another path
    public func startsWith(_ other: TopicPath) -> Bool {
        guard networkId == other.networkId else { return false }
        guard segmentCount >= other.segmentCount else { return false }

        for (index, otherSegment) in other.segments.enumerated() {
            let thisSegment = segments[index]
            switch (thisSegment, otherSegment) {
            case (.literal(let this), .literal(let other)):
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
            let templatePath = try TopicPath.parse("\(networkId):\(template)")

            // Must have same number of segments
            guard segmentCount == templatePath.segmentCount else { return false }

            // Check each segment for template matching
            for (thisSegment, templateSegment) in zip(segments, templatePath.segments) {
                switch (thisSegment, templateSegment) {
                case (.literal(let this), .literal(let template)):
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
            let templatePath = try TopicPath.parse("\(networkId):\(template)")

            guard segmentCount == templatePath.segmentCount else { return nil }

            var params: [String: String] = [:]

            for (thisSegment, templateSegment) in zip(segments, templatePath.segments) {
                switch (thisSegment, templateSegment) {
                case (.literal(let this), .literal(let template)):
                    if this != template { return nil }
                case (.literal(let value), .template(let paramName)):
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
                                    networkId: String = "default") throws -> TopicPath {
        let segments = template.split(separator: "/").map(String.init)
        var resolvedSegments: [String] = []

        for segment in segments {
            if segment.hasPrefix("{") && segment.hasSuffix("}") {
                let paramName = String(segment.dropFirst().dropLast())
                guard let paramValue = params[paramName] else {
                    throw TopicPathError.missingTemplateParameter("Missing parameter: \(paramName)")
                }
                resolvedSegments.append(paramValue)
            } else {
                resolvedSegments.append(segment)
            }
        }

        return try TopicPath(networkId: networkId, segments: resolvedSegments)
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
                                 pathSegments: [PathSegment]? = nil) -> Bool {
        let actualPathSegments = pathSegments ?? segments

        // If we've consumed both pattern and path, we have a match
        if patternIndex == patternSegments.count && pathIndex == actualPathSegments.count {
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
            for nextPathIndex in pathIndex...actualPathSegments.count where
                matchesSegments(patternSegments, patternIndex: patternIndex + 1,
                                pathIndex: nextPathIndex, pathSegments: actualPathSegments) {
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

    /// Helper for test compatibility
    public static func testDefault(_ path: String) -> TopicPath {
        do {
            return try TopicPath.parse("default:\(path)")
        } catch {
            // For test compatibility, return a minimal valid path if parsing fails
            return TopicPath(
                rawPath: "default:\(path)",
                networkId: "default",
                segments: [.literal(path)],
                isPattern: false,
                hasTemplates: false,
                servicePath: path,
                actionPath: path,
                segmentCount: 1,
                hashComponents: [0],
                segmentTypeBitmap: 0
            )
        }
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
        if case (.literal(let this), .literal(let other)) = (self, other) {
            return this == other
        }

        // Use type-based matching to reduce complexity
        return matchesByType(other)
    }

    private func matchesByType(_ other: PathSegment) -> Bool {
        switch self {
        case .literal:
            return false // Literal can only match identical literal
        case .template:
            return other.isLiteral || other.isTemplate
        case .singleWildcard:
            return other.isLiteral || other.isTemplate || other.isSingleWildcard
        case .multiWildcard:
            return other.isLiteral || other.isTemplate || other.isMultiWildcard
        }
    }

    private var isLiteral: Bool {
        if case .literal = self { return true }
        return false
    }

    private var isTemplate: Bool {
        if case .template = self { return true }
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
