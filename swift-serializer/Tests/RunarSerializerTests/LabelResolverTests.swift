import RunarSerializer
import XCTest

/// Tests for the Swift-side Label Resolver implementation
final class LabelResolverTests: XCTestCase {
    // MARK: - Test Data

    private let testNetworkKey = Data(Array(0 ..< 32)) // Exactly 32 bytes
    private let testProfileKey1 = Data(Array(10 ..< 42)) // Exactly 32 bytes
    private let testProfileKey2 = Data(Array(20 ..< 52)) // Exactly 32 bytes

    // MARK: - LabelResolverConfig Tests

    func testLabelResolverConfigValidation() throws {
        // Test empty config
        let emptyConfig = LabelResolverConfig(labelMappings: [:])
        XCTAssertThrowsError(try LabelResolver.createContextResolver(
            systemConfig: emptyConfig,
            userProfilePublicKeys: []
        )) { error in
            XCTAssertTrue(error is LabelResolverError)
            if case let .invalidConfiguration(message) = error as? LabelResolverError {
                XCTAssertTrue(message.contains("labelMappings must not be empty"))
            }
        }

        // Test valid config
        let validConfig = LabelResolverConfig(labelMappings: [
            "system": LabelValue(networkPublicKey: testNetworkKey, userKeySpec: .currentUser),
            "user": LabelValue(networkPublicKey: nil, userKeySpec: .currentUser),
            "search": LabelValue(networkPublicKey: testNetworkKey, userKeySpec: nil),
        ])

        let resolver = try LabelResolver.createContextResolver(
            systemConfig: validConfig,
            userProfilePublicKeys: [testProfileKey1, testProfileKey2]
        )

        XCTAssertTrue(resolver.canResolve("system"))
        XCTAssertTrue(resolver.canResolve("user"))
        XCTAssertTrue(resolver.canResolve("search"))
        XCTAssertFalse(resolver.canResolve("nonexistent"))
    }

    func testLabelResolverConfigInvalidLabels() throws {
        // Test label with neither network key nor user spec
        let invalidConfig = LabelResolverConfig(labelMappings: [
            "invalid": LabelValue(networkPublicKey: nil, userKeySpec: nil),
        ])

        XCTAssertThrowsError(try LabelResolver.createContextResolver(
            systemConfig: invalidConfig,
            userProfilePublicKeys: []
        )) { error in
            XCTAssertTrue(error is LabelResolverError)
            if case let .invalidConfiguration(message) = error as? LabelResolverError {
                XCTAssertTrue(message.contains("must specify either networkPublicKey or userKeySpec"))
            }
        }

        // Test empty network key
        let emptyNetworkConfig = LabelResolverConfig(labelMappings: [
            "empty_network": LabelValue(networkPublicKey: Data(), userKeySpec: .currentUser),
        ])

        XCTAssertThrowsError(try LabelResolver.createContextResolver(
            systemConfig: emptyNetworkConfig,
            userProfilePublicKeys: [testProfileKey1]
        )) { error in
            XCTAssertTrue(error is LabelResolverError)
            if case let .invalidConfiguration(message) = error as? LabelResolverError {
                XCTAssertTrue(message.contains("has empty networkPublicKey"))
            }
        }
    }

    func testLabelResolverKeyResolution() throws {
        let config = LabelResolverConfig(labelMappings: [
            "system": LabelValue(networkPublicKey: testNetworkKey, userKeySpec: .currentUser),
            "user_only": LabelValue(networkPublicKey: nil, userKeySpec: .currentUser),
            "network_only": LabelValue(networkPublicKey: testNetworkKey, userKeySpec: nil),
        ])

        let resolver = try LabelResolver.createContextResolver(
            systemConfig: config,
            userProfilePublicKeys: [testProfileKey1, testProfileKey2]
        )

        // Test system label (both network and user keys)
        let systemInfo = try resolver.resolveLabelInfo("system")
        XCTAssertEqual(systemInfo.networkPublicKey, testNetworkKey)
        XCTAssertEqual(systemInfo.profilePublicKeys, [testProfileKey1, testProfileKey2])

        // Test user-only label
        let userInfo = try resolver.resolveLabelInfo("user_only")
        XCTAssertNil(userInfo.networkPublicKey)
        XCTAssertEqual(userInfo.profilePublicKeys, [testProfileKey1, testProfileKey2])

        // Test network-only label
        let networkInfo = try resolver.resolveLabelInfo("network_only")
        XCTAssertEqual(networkInfo.networkPublicKey, testNetworkKey)
        XCTAssertTrue(networkInfo.profilePublicKeys.isEmpty)

        // Test unavailable label
        XCTAssertThrowsError(try resolver.resolveLabelInfo("nonexistent")) { error in
            XCTAssertTrue(error is LabelResolverError)
            if case let .labelUnavailable(label) = error as? LabelResolverError {
                XCTAssertEqual(label, "nonexistent")
            }
        }
    }

    func testLabelResolverAvailableLabels() throws {
        let config = LabelResolverConfig(labelMappings: [
            "zebra": LabelValue(networkPublicKey: testNetworkKey, userKeySpec: nil),
            "apple": LabelValue(networkPublicKey: nil, userKeySpec: .currentUser),
            "banana": LabelValue(networkPublicKey: testNetworkKey, userKeySpec: .currentUser),
        ])

        let resolver = try LabelResolver.createContextResolver(
            systemConfig: config,
            userProfilePublicKeys: [testProfileKey1]
        )

        let availableLabels = resolver.availableLabels()
        XCTAssertEqual(availableLabels, ["apple", "banana", "zebra"]) // Should be sorted
    }

    func testLabelResolverCustomKeyword() throws {
        let config = LabelResolverConfig(labelMappings: [
            "custom": LabelValue(networkPublicKey: testNetworkKey, userKeySpec: .custom("customResolver")),
        ])

        XCTAssertThrowsError(try LabelResolver.createContextResolver(
            systemConfig: config,
            userProfilePublicKeys: [testProfileKey1]
        )) { error in
            XCTAssertTrue(error is LabelResolverError)
            if case let .invalidConfiguration(message) = error as? LabelResolverError {
                XCTAssertTrue(message.contains("Custom userKeySpec 'customResolver' requires explicit pre-resolution"))
            }
        }
    }

    func testLabelResolverKeyValidation() throws {
        // Test invalid key length
        let shortKey = Data("short".utf8)
        let config = LabelResolverConfig(labelMappings: [
            "invalid_key": LabelValue(networkPublicKey: shortKey, userKeySpec: nil),
        ])

        XCTAssertThrowsError(try LabelResolver.createContextResolver(
            systemConfig: config,
            userProfilePublicKeys: []
        )) { error in
            XCTAssertTrue(error is LabelResolverError)
            if case let .invalidConfiguration(message) = error as? LabelResolverError {
                XCTAssertTrue(message.contains("must be 32 bytes"))
            }
        }
    }
}
