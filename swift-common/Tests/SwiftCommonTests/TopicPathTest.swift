import Testing
@testable import SwiftCommon

/// Comprehensive test suite for TopicPath
///
/// INTENTION: Verify that TopicPath correctly handles path parsing, manipulation,
/// and validation according to documented requirements. Covers all methods and edge cases.
@Suite("TopicPath Tests")
struct TopicPathTest {

    /// Test TopicPath::new() constructor with various valid inputs
    @Test
    func testNewValidPaths() throws {
        // Test with network_id prefix
        let path = try TopicPath(networkId: "main", segments: ["auth", "login"])
        #expect(path.networkId == "main")
        #expect(path.servicePath == "auth")
        #expect(path.actionPath == "auth/login")
        #expect(path.asString() == "main:auth/login")
        #expect(path.segmentCount == 2)

        // Test without network_id (uses default)
        let path2 = try TopicPath(networkId: "default", segments: ["auth", "login"])
        #expect(path2.networkId == "default")
        #expect(path2.servicePath == "auth")
        #expect(path2.actionPath == "auth/login")
        #expect(path2.asString() == "default:auth/login")

        // Test with just service name
        let path3 = try TopicPath(networkId: "main", segments: ["auth"])
        #expect(path3.networkId == "main")
        #expect(path3.servicePath == "auth")
        #expect(path3.actionPath == "")
        #expect(path3.asString() == "main:auth")
        #expect(path3.segmentCount == 1)

        // Test with multiple path segments
        let path4 = try TopicPath(networkId: "main", segments: ["auth", "users", "details"])
        #expect(path4.networkId == "main")
        #expect(path4.servicePath == "auth")
        #expect(path4.actionPath == "auth/users/details")
        #expect(path4.segmentCount == 3)
    }

    /// Test TopicPath::new() constructor with invalid inputs
    @Test
    func testNewInvalidPaths() throws {
        // Empty path
        #expect(throws: TopicPathError.self) {
            try TopicPath(networkId: "", segments: [])
        }

        // Empty network ID
        #expect(throws: TopicPathError.self) {
            try TopicPath(networkId: "", segments: ["auth", "login"])
        }

        // Multiple colons in network ID should be invalid
        #expect(throws: TopicPathError.self) {
            try TopicPath.parse("main:sub:auth/login")
        }
    }

    /// Test TopicPath::newService() constructor
    @Test
    func testNewService() throws {
        let path = try TopicPath.newService("main", serviceName: "auth")
        #expect(path.networkId == "main")
        #expect(path.servicePath == "auth")
        #expect(path.actionPath == "")
        #expect(path.asString() == "main:auth")
        #expect(path.segmentCount == 1)
    }

    /// Test TopicPath::child() for creating child paths
    @Test
    func testChild() throws {
        // Create a base path and add a child
        let base = try TopicPath(networkId: "main", segments: ["auth"])
        let child = try base.child("login")

        #expect(child.asString() == "main:auth/login")
        #expect(child.networkId == "main")
        #expect(child.servicePath == "auth")
        #expect(child.actionPath == "auth/login")
        #expect(child.segmentCount == 2)

        // Add another child
        let nestedChild = try child.child("advanced")
        #expect(nestedChild.asString() == "main:auth/login/advanced")
        #expect(nestedChild.segmentCount == 3)

        // Test invalid child (with slash)
        #expect(throws: TopicPathError.self) {
            try base.child("invalid/segment")
        }
    }

    /// Test TopicPath::parent() for creating parent paths
    @Test
    func testParent() throws {
        // Create a nested path
        let path = try TopicPath(networkId: "main", segments: ["auth", "users", "details"])

        // Get parent (one level up)
        let parent = try path.parent()
        #expect(parent?.asString() == "main:auth/users")
        #expect(parent?.servicePath == "auth")
        #expect(parent?.segmentCount == 2)

        // Get grandparent (two levels up)
        let grandparent = try parent?.parent()
        #expect(grandparent?.asString() == "main:auth")
        #expect(grandparent?.segmentCount == 1)

        // Cannot get parent of root path
        let rootPath = try TopicPath(networkId: "main", segments: ["auth"])
        #expect(try rootPath.parent() == nil)

        // Cannot get parent of service-only path
        #expect(try rootPath.parent() == nil)
    }

    /// Test TopicPath::startsWith() for path prefix matching
    @Test
    func testStartsWith() throws {
        let path = try TopicPath(networkId: "main", segments: ["auth", "users", "list"])

        // Test with matching prefixes
        let prefix1 = try TopicPath(networkId: "main", segments: ["auth"])
        let prefix2 = try TopicPath(networkId: "main", segments: ["auth", "users"])

        #expect(path.startsWith(prefix1))
        #expect(path.startsWith(prefix2))

        // Test with non-matching prefixes
        let differentNetwork = try TopicPath(networkId: "other", segments: ["auth", "users"])
        let differentService = try TopicPath(networkId: "main", segments: ["payments"])

        #expect(!path.startsWith(differentNetwork))
        #expect(!path.startsWith(differentService))

        // Test with longer prefix than path
        let longerPrefix = try TopicPath(networkId: "main", segments: ["auth", "users", "list", "extra"])
        #expect(!path.startsWith(longerPrefix))
    }

    /// Test TopicPath::getSegments() for path segment extraction
    @Test
    func testGetSegments() throws {
        // Simple path
        let path1 = try TopicPath(networkId: "main", segments: ["auth", "login"])
        #expect(path1.segments.count == 2)
        #expect(path1.segments[0] == .literal("auth"))
        #expect(path1.segments[1] == .literal("login"))

        // Complex path with multiple segments
        let path2 = try TopicPath(networkId: "main", segments: ["auth", "users", "profile", "edit"])
        #expect(path2.segments.count == 4)
        #expect(path2.segments[0] == .literal("auth"))
        #expect(path2.segments[1] == .literal("users"))
        #expect(path2.segments[2] == .literal("profile"))
        #expect(path2.segments[3] == .literal("edit"))

        // Path with service name only
        let path3 = try TopicPath(networkId: "main", segments: ["auth"])
        #expect(path3.segments.count == 1)
        #expect(path3.segments[0] == .literal("auth"))
    }

    /// Test TopicPath::testDefault() helper for tests
    @Test
    func testDefaultHelper() throws {
        let path = TopicPath.testDefault("auth/login")
        #expect(path.networkId == "default")
        #expect(path.servicePath == "auth")
        #expect(path.actionPath == "auth/login")
        #expect(path.asString() == "default:auth/login")
    }

    /// Test consistency between methods
    @Test
    func testMethodConsistency() throws {
        let path = try TopicPath(networkId: "main", segments: ["service", "action"])

        // The service_path should return just the service name (first segment)
        #expect(path.servicePath == "service")

        // The segments should include all parts
        #expect(path.segments.count == 2)
        #expect(path.segments[0] == .literal("service"))
        #expect(path.segments[1] == .literal("action"))

        // The action_path should include everything after the network ID
        #expect(path.actionPath == "service/action")
    }

    /// Test with unusual but valid paths
    @Test
    func testUnusualPaths() throws {
        // Network ID with special characters
        let path1 = try TopicPath(networkId: "test-network_01", segments: ["service"])
        #expect(path1.networkId == "test-network_01")
        #expect(path1.servicePath == "service")

        // Service path with special characters
        let path2 = try TopicPath(networkId: "main", segments: ["my-service_01"])
        #expect(path2.servicePath == "my-service_01")

        // Long paths with many segments
        let path3 = try TopicPath(networkId: "main", segments: ["service", "a", "b", "c", "d", "e", "f"])
        #expect(path3.segmentCount == 7)
        #expect(path3.actionPath == "service/a/b/c/d/e/f")
    }

    /// Test service paths with embedded slashes
    @Test
    func testServicePathsWithSlashes() throws {
        // Test with internal service path using $ prefix
        let path = try TopicPath.parse("test_network:$registry/services/list")

        // The service_path should be "$registry" - first segment only
        #expect(path.servicePath == "$registry")

        // Verify the action_path includes the complete path after network ID
        #expect(path.actionPath == "$registry/services/list")
    }

    /// Test with internal registry service path using $ prefix
    @Test
    func testRegistryServicePaths() throws {
        // Create a service with $ prefix path
        let servicePath = "$registry"

        // Register action with path "services/list"
        let actionPath = "services/list"

        // The full action path that should be constructed when handling requests
        let expectedFullPath = "test_network:$registry/services/list"

        // Simulate how paths should be handled
        let path = try TopicPath.parse("test_network:\(servicePath)/\(actionPath)")

        #expect(path.asString() == expectedFullPath)
    }

    @Test
    func testNewActionTopic() throws {
        // Create a service path
        let servicePath = try TopicPath(networkId: "main", segments: ["auth"])

        // Create an action path
        let actionPath = try servicePath.newActionTopic("login")

        // Verify the path components
        #expect(actionPath.networkId == "main")
        #expect(actionPath.servicePath == "auth")
        #expect(actionPath.actionPath == "auth/login")
    }

    @Test
    func testNewEventTopic() throws {
        // Create a service path
        let servicePath = try TopicPath(networkId: "main", segments: ["auth"])

        // Create an event path
        let eventPath = try servicePath.newEventTopic("user_logged_in")

        // Verify the path components
        #expect(eventPath.networkId == "main")
        #expect(eventPath.servicePath == "auth")
        #expect(eventPath.actionPath == "auth/user_logged_in")
    }

    @Test
    func testNestedActionPath() throws {
        // Create a nested service path
        let servicePath = try TopicPath(networkId: "main", segments: ["serviceX"])

        let actionResult = try servicePath.newActionTopic("verify_token")
        #expect(actionResult.networkId == "main")
        #expect(actionResult.servicePath == "serviceX")
        #expect(actionResult.actionPath == "serviceX/verify_token")
    }

    @Test
    func testNestedInvalidActionPath() throws {
        // Create a nested service with action already
        let servicePath = try TopicPath(networkId: "main", segments: ["services", "auth"])

        // Creating an action path from a topic path with action already is not allowed
        #expect(throws: TopicPathError.self) {
            try servicePath.newActionTopic("verify_token")
        }
    }

    @Test
    func testDefaultNetworkId() throws {
        // Create a service path with default network ID
        let servicePath = try TopicPath(networkId: "test-network", segments: ["auth"])

        // Create an action path
        let actionPath = try servicePath.newActionTopic("login")

        // Verify the network ID was preserved
        #expect(actionPath.networkId == "test-network")
        #expect(actionPath.servicePath == "auth")
        #expect(actionPath.actionPath == "auth/login")
    }

    @Test
    func testInvalidActionName() throws {
        // Create a service path
        let servicePath = try TopicPath(networkId: "main", segments: ["auth"])

        // Try to create an action path with an invalid name (containing a colon)
        #expect(throws: TopicPathError.self) {
            try servicePath.newActionTopic("invalid:name")
        }
    }

    // Test basic path parsing
    @Test
    func testBasicParse() throws {
        // Parse a path with network ID and action
        let path = try TopicPath.parse("default:auth/login")
        #expect(path.networkId == "default")
        #expect(path.servicePath == "auth")
        #expect(path.actionPath == "auth/login")
        #expect(path.asString() == "default:auth/login")
    }

    // Test with various path formats
    @Test
    func testVariousFormats() throws {
        // Format 1: Full path with network ID and action
        let path1 = try TopicPath.parse("network:auth/login")
        #expect(path1.networkId == "network")
        #expect(path1.servicePath == "auth")
        #expect(path1.actionPath == "auth/login")

        // Format 2: Network and service only
        let path2 = try TopicPath.parse("network:auth")
        #expect(path2.networkId == "network")
        #expect(path2.servicePath == "auth")
        #expect(path2.actionPath == "")

        // Format 3: Service and action without network (uses default)
        let path3 = try TopicPath.parse("auth/login")
        #expect(path3.networkId == "default")
        #expect(path3.servicePath == "auth")
        #expect(path3.actionPath == "auth/login")
    }
}
