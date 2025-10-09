@testable import SwiftCommon
import Testing

/// INTENTION: Test comprehensive scenarios for wildcard pattern matching in TopicPath
@Suite("TopicPath Wildcard Tests")
struct TopicPathWildcardTest {
    @Test
    func testIsPattern() throws {
        // Test without wildcards
        let path1 = try TopicPath.new("services/auth/login", defaultNetwork: "main")
        #expect(!path1.isPattern)

        // Test with single-segment wildcard
        let pattern1 = try TopicPath.new("services/*/login", defaultNetwork: "main")
        #expect(pattern1.isPattern)

        // Test with multi-segment wildcard
        let pattern2 = try TopicPath.new("services/>", defaultNetwork: "main")
        #expect(pattern2.isPattern)
        #expect(pattern2.segments.last == .multiWildcard)
    }

    @Test
    func singleWildcardMatching() throws {
        // Create pattern with single-segment wildcard
        let pattern = try TopicPath.new("services/*/state", defaultNetwork: "main")

        // Test successful matches
        let path1 = try TopicPath.new("services/auth/state", defaultNetwork: "main")
        let path2 = try TopicPath.new("services/math/state", defaultNetwork: "main")

        #expect(pattern.matches(path1))
        #expect(pattern.matches(path2))

        // Test non-matches
        let nonMatch1 = try TopicPath.new("services/auth/login", defaultNetwork: "main")
        let nonMatch2 = try TopicPath.new("services/auth/state/active", defaultNetwork: "main")
        let nonMatch3 = try TopicPath.new("events/user/created", defaultNetwork: "main")

        #expect(!pattern.matches(nonMatch1)) // Different last segment
        #expect(!pattern.matches(nonMatch2)) // Too many segments
        #expect(!pattern.matches(nonMatch3)) // Different service path
    }

    @Test
    func multiWildcardMatching() throws {
        // Create pattern with multi-segment wildcard
        let pattern = try TopicPath.new("services/>", defaultNetwork: "main")

        // Test successful matches (should match any path that starts with "services")
        let path1 = try TopicPath.new("services/auth", defaultNetwork: "main")
        let path2 = try TopicPath.new("services/auth/login", defaultNetwork: "main")
        let path3 = try TopicPath.new("services/math/add/numbers", defaultNetwork: "main")

        #expect(pattern.matches(path1))
        #expect(pattern.matches(path2))
        #expect(pattern.matches(path3))

        // Test non-matches
        let nonMatch1 = try TopicPath.new("events/user/created", defaultNetwork: "main")

        #expect(!pattern.matches(nonMatch1)) // Different service path
    }

    @Test
    func multiWildcardPosition() throws {
        // Multi-wildcard must be the last segment
        #expect(throws: TopicPathError.self) {
            try TopicPath.new("services/>/state", defaultNetwork: "main")
        }

        // But can be in the middle of a pattern as long as it's the last segment
        let validPattern = try TopicPath.new("services/>", defaultNetwork: "main")
        #expect(validPattern.isPattern)
        #expect(validPattern.segments.last == .multiWildcard)
    }

    @Test
    func complexPatterns() throws {
        // Pattern with both types of wildcards
        let pattern = try TopicPath.new("services/*/events/>", defaultNetwork: "main")

        // Test successful matches
        let path1 = try TopicPath.new("services/auth/events/user/login", defaultNetwork: "main")
        let path2 = try TopicPath.new("services/math/events/calculation/completed", defaultNetwork: "main")

        #expect(pattern.matches(path1))
        #expect(pattern.matches(path2))

        // Test non-matches
        let nonMatch1 = try TopicPath.new("services/auth/state", defaultNetwork: "main")
        let nonMatch2 = try TopicPath.new("services/auth/logs/error", defaultNetwork: "main")

        #expect(!pattern.matches(nonMatch1)) // Different segment after service
        #expect(!pattern.matches(nonMatch2)) // "logs" instead of "events"
    }

    @Test
    func wildcardAtBeginning() throws {
        // Pattern with wildcard at beginning
        let pattern = try TopicPath.new("*/state", defaultNetwork: "main")

        // Test successful matches (should match any service with "state" action)
        let path1 = try TopicPath.new("auth/state", defaultNetwork: "main")
        let path2 = try TopicPath.new("math/state", defaultNetwork: "main")

        #expect(pattern.matches(path1))
        #expect(pattern.matches(path2))

        // Test non-matches
        let nonMatch1 = try TopicPath.new("auth/login", defaultNetwork: "main")

        #expect(!pattern.matches(nonMatch1)) // Different action
    }

    @Test
    func networkIsolation() throws {
        // Patterns should only match within the same network
        let pattern = try TopicPath.new("services/*/state", defaultNetwork: "main")
        let path1 = try TopicPath.new("services/auth/state", defaultNetwork: "main")
        let path2 = try TopicPath.new("services/auth/state", defaultNetwork: "other")

        #expect(pattern.matches(path1)) // Same network
        #expect(!pattern.matches(path2)) // Different network
    }

    @Test
    func efficientWildcardPatternLookup() throws {
        // Create a HashMap to store handlers by path pattern
        var handlers: [String: String] = [:]
        let networkId = "main"

        // Store handlers with template patterns
        let template1 = try TopicPath.new("services/{service_path}/state", defaultNetwork: networkId)
        let template2 = try TopicPath.new("services/*/state", defaultNetwork: networkId)

        handlers[template1.asString()] = "TEMPLATE_HANDLER_1"
        handlers[template2.asString()] = "WILDCARD_HANDLER"

        // Create a concrete path to look up
        let concretePath = try TopicPath.new("services/math/state", defaultNetwork: networkId)

        // Generate possible template patterns from the concrete path
        // This is the key insight - we can pre-compute all possible template patterns
        // that might match our concrete path, then look them up directly
        let possibleTemplates = generatePossibleTemplates(concretePath)

        // Look up each possible template pattern
        for template in possibleTemplates {
            if let handler = handlers[template] {
                print("Found handler for template: \(template)")
                print("Handler: \(handler)")
                // Found a matching handler, use it
                return
            }
        }

        #expect(Bool(false), "No matching template found for \(concretePath)")
    }

    @Test
    func efficientMultiWildcardPatternLookup() throws {
        // Create a HashMap to store handlers by path pattern
        var handlers: [String: String] = [:]
        let networkId = "main"

        // Store handlers with wildcard patterns
        let wildcard1 = try TopicPath.new("services/*/events", defaultNetwork: networkId)
        let wildcard2 = try TopicPath.new("services/>", defaultNetwork: networkId)

        handlers[wildcard1.asString()] = "SINGLE_WILDCARD_HANDLER"
        handlers[wildcard2.asString()] = "MULTI_WILDCARD_HANDLER"

        // Create a concrete path to look up
        let concretePath = try TopicPath.new("services/math/events", defaultNetwork: networkId)

        // Generate possible wildcard patterns from the concrete path
        let possiblePatterns = generateWildcardPatterns(concretePath)

        // Look up each possible pattern
        var foundHandler = false
        for pattern in possiblePatterns {
            if let handler = handlers[pattern] {
                print("Found handler for wildcard pattern: \(pattern)")
                print("Handler: \(handler)")
                foundHandler = true
                break
            }
        }

        #expect(foundHandler, "No matching wildcard handler found for \(concretePath)")
    }
}

// Helper functions for wildcard tests
private func generatePossibleTemplates(_ path: TopicPath) -> [String] {
    // For this example, we'll manually create the patterns we know should match
    // In a real implementation, we would generate these systematically

    let concretePath = path.asString()
    var templates: [String] = []

    // Add the concrete path itself (for exact matching)
    templates.append(concretePath)

    // Extract segments (network_id:path/to/resource)
    if let pathPart = concretePath.split(separator: ":").last {
        let segments: [String] = pathPart.split(separator: "/").map(String.init)

        // Create specific template patterns based on the segments
        if segments.count >= 3, segments[0] == "services" {
            // Create services/{service_path}/state pattern
            let networkId = concretePath.split(separator: ":").first ?? "main"
            let template = "\(networkId):services/{service_path}/state"
            templates.append(template)
        }
    }

    return templates
}

private func generateWildcardPatterns(_ path: TopicPath) -> [String] {
    let concretePath = path.asString()
    var patterns: [String] = []

    // Add the concrete path itself
    patterns.append(concretePath)

    // Extract segments (network_id:path/to/resource)
    if let networkPrefix = concretePath.split(separator: ":").first,
       let pathPart = concretePath.split(separator: ":").last
    {
        let segments: [String] = pathPart.split(separator: "/").map(String.init)

        // Generate wildcards based on structure
        if segments.count >= 3, segments[0] == "services" {
            // Replace the middle segment with a * wildcard
            let wildcardMiddle = "\(networkPrefix):services/*/\(segments[2...].joined(separator: "/"))"
            patterns.append(wildcardMiddle)

            // Add a multi-segment wildcard pattern
            patterns.append("\(networkPrefix):services/>")
        }
    }

    return patterns
}
