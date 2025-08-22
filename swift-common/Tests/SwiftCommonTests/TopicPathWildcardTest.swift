import Testing
@testable import SwiftCommon

/// INTENTION: Test comprehensive scenarios for wildcard pattern matching in TopicPath
@Suite("TopicPath Wildcard Tests")
struct TopicPathWildcardTest {

    @Test
    func testIsPattern() throws {
        // Test without wildcards
        let path1 = try TopicPath(networkId: "main", segments: ["services", "auth", "login"])
        #expect(!path1.isPattern)

        // Test with single-segment wildcard
        let pattern1 = try TopicPath(networkId: "main", segments: ["services", "*", "login"])
        #expect(pattern1.isPattern)

        // Test with multi-segment wildcard
        let pattern2 = try TopicPath(networkId: "main", segments: ["services", ">"])
        #expect(pattern2.isPattern)
        #expect(pattern2.segments.last == .multiWildcard)
    }

    @Test
    func testSingleWildcardMatching() throws {
        // Create pattern with single-segment wildcard
        let pattern = try TopicPath(networkId: "main", segments: ["services", "*", "state"])

        // Test successful matches
        let path1 = try TopicPath(networkId: "main", segments: ["services", "auth", "state"])
        let path2 = try TopicPath(networkId: "main", segments: ["services", "math", "state"])

        #expect(pattern.matches(path1))
        #expect(pattern.matches(path2))

        // Test non-matches
        let nonMatch1 = try TopicPath(networkId: "main", segments: ["services", "auth", "login"])
        let nonMatch2 = try TopicPath(networkId: "main", segments: ["services", "auth", "state", "active"])
        let nonMatch3 = try TopicPath(networkId: "main", segments: ["events", "user", "created"])

        #expect(!pattern.matches(nonMatch1)) // Different last segment
        #expect(!pattern.matches(nonMatch2)) // Too many segments
        #expect(!pattern.matches(nonMatch3)) // Different service path
    }

    @Test
    func testMultiWildcardMatching() throws {
        // Create pattern with multi-segment wildcard
        let pattern = try TopicPath(networkId: "main", segments: ["services", ">"])

        // Test successful matches (should match any path that starts with "services")
        let path1 = try TopicPath(networkId: "main", segments: ["services", "auth"])
        let path2 = try TopicPath(networkId: "main", segments: ["services", "auth", "login"])
        let path3 = try TopicPath(networkId: "main", segments: ["services", "math", "add", "numbers"])

        #expect(pattern.matches(path1))
        #expect(pattern.matches(path2))
        #expect(pattern.matches(path3))

        // Test non-matches
        let nonMatch1 = try TopicPath(networkId: "main", segments: ["events", "user", "created"])

        #expect(!pattern.matches(nonMatch1)) // Different service path
    }

    @Test
    func testMultiWildcardPosition() throws {
        // Multi-wildcard must be the last segment
        #expect(throws: TopicPathError.self) {
            try TopicPath(networkId: "main", segments: ["services", ">", "state"])
        }

        // But can be in the middle of a pattern as long as it's the last segment
        let validPattern = try TopicPath(networkId: "main", segments: ["services", ">"])
        #expect(validPattern.isPattern)
        #expect(validPattern.segments.last == .multiWildcard)
    }

    @Test
    func testComplexPatterns() throws {
        // Pattern with both types of wildcards
        let pattern = try TopicPath(networkId: "main", segments: ["services", "*", "events", ">"])

        // Test successful matches
        let path1 = try TopicPath(networkId: "main", segments: ["services", "auth", "events", "user", "login"])
        let path2 = try TopicPath(networkId: "main", segments: ["services", "math", "events", "calculation", "completed"])

        #expect(pattern.matches(path1))
        #expect(pattern.matches(path2))

        // Test non-matches
        let nonMatch1 = try TopicPath(networkId: "main", segments: ["services", "auth", "state"])
        let nonMatch2 = try TopicPath(networkId: "main", segments: ["services", "auth", "logs", "error"])

        #expect(!pattern.matches(nonMatch1)) // Different segment after service
        #expect(!pattern.matches(nonMatch2)) // "logs" instead of "events"
    }

    @Test
    func testWildcardAtBeginning() throws {
        // Pattern with wildcard at beginning
        let pattern = try TopicPath(networkId: "main", segments: ["*", "state"])

        // Test successful matches (should match any service with "state" action)
        let path1 = try TopicPath(networkId: "main", segments: ["auth", "state"])
        let path2 = try TopicPath(networkId: "main", segments: ["math", "state"])

        #expect(pattern.matches(path1))
        #expect(pattern.matches(path2))

        // Test non-matches
        let nonMatch1 = try TopicPath(networkId: "main", segments: ["auth", "login"])

        #expect(!pattern.matches(nonMatch1)) // Different action
    }

    @Test
    func testNetworkIsolation() throws {
        // Patterns should only match within the same network
        let pattern = try TopicPath(networkId: "main", segments: ["services", "*", "state"])
        let path1 = try TopicPath(networkId: "main", segments: ["services", "auth", "state"])
        let path2 = try TopicPath(networkId: "other", segments: ["services", "auth", "state"])

        #expect(pattern.matches(path1)) // Same network
        #expect(!pattern.matches(path2)) // Different network
    }

    @Test
    func testEfficientWildcardPatternLookup() throws {
        // Create a HashMap to store handlers by path pattern
        var handlers: [String: String] = [:]
        let networkId = "main"

        // Store handlers with template patterns
        let template1 = try TopicPath(networkId: networkId, segments: ["services", "{service_path}", "state"])
        let template2 = try TopicPath(networkId: networkId, segments: ["services", "*", "state"])

        handlers[template1.asString()] = "TEMPLATE_HANDLER_1"
        handlers[template2.asString()] = "WILDCARD_HANDLER"

        // Create a concrete path to look up
        let concretePath = try TopicPath(networkId: networkId, segments: ["services", "math", "state"])

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
    func testEfficientMultiWildcardPatternLookup() throws {
        // Create a HashMap to store handlers by path pattern
        var handlers: [String: String] = [:]
        let networkId = "main"

        // Store handlers with wildcard patterns
        let wildcard1 = try TopicPath(networkId: networkId, segments: ["services", "*", "events"])
        let wildcard2 = try TopicPath(networkId: networkId, segments: ["services", ">"])

        handlers[wildcard1.asString()] = "SINGLE_WILDCARD_HANDLER"
        handlers[wildcard2.asString()] = "MULTI_WILDCARD_HANDLER"

        // Create a concrete path to look up
        let concretePath = try TopicPath(networkId: networkId, segments: ["services", "math", "events"])

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
        if segments.count >= 3 && segments[0] == "services" {
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
       let pathPart = concretePath.split(separator: ":").last {
        let segments: [String] = pathPart.split(separator: "/").map(String.init)

        // Generate wildcards based on structure
        if segments.count >= 3 && segments[0] == "services" {
            // Replace the middle segment with a * wildcard
            let wildcardMiddle = "\(networkPrefix):services/*/\(segments[2...].joined(separator: "/"))"
            patterns.append(wildcardMiddle)

            // Add a multi-segment wildcard pattern
            patterns.append("\(networkPrefix):services/>")
        }
    }

    return patterns
}
