import Foundation

// MARK: - Label Resolution Types

/// Keywords for dynamic label resolution
public enum LabelKeyword: Equatable, Sendable {
    /// Maps to current user's profile public keys from request context
    case currentUser
    /// Reserved for future custom resolution functions
    case custom(String)
}

/// Value specification for a label
public struct LabelValue: Sendable, Equatable {
    /// Optional network public key for this label
    /// If nil, will use empty key for user-only labels
    public let networkPublicKey: Data?
    /// Optional user key specification for this label
    public let userKeySpec: LabelKeyword?

    public init(networkPublicKey: Data?, userKeySpec: LabelKeyword?) {
        self.networkPublicKey = networkPublicKey
        self.userKeySpec = userKeySpec
    }
}

/// Configuration for label resolver system labels
public struct LabelResolverConfig: Sendable, Equatable {
    /// Static label mappings for system labels
    /// These are config-driven and known at startup
    /// Supports both direct network public keys and dynamic keywords
    public let labelMappings: [String: LabelValue]

    public init(labelMappings: [String: LabelValue]) {
        self.labelMappings = labelMappings
    }
}

// MARK: - Label Resolver Errors

public enum LabelResolverError: Error, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case labelUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(msg):
            "Invalid label resolver configuration: \(msg)"
        case let .labelUnavailable(label):
            "Label unavailable: \(label)"
        }
    }
}

// MARK: - Label Resolver Implementation

/// Immutable, value-type resolver with constant-time lookups. Thread-safe by design with no internal mutation.
public struct LabelResolver: Sendable, Equatable {
    private let mapping: [String: LabelKeyInfo]

    public init(mapping: [String: LabelKeyInfo]) {
        self.mapping = mapping
    }

    /// Check if a label can be resolved
    public func canResolve(_ label: String) -> Bool {
        mapping[label] != nil
    }

    /// Resolve a label to key-info (public key + scope)
    public func resolveLabelInfo(_ label: String) throws -> LabelKeyInfo {
        guard let info = mapping[label] else {
            throw LabelResolverError.labelUnavailable(label)
        }
        return info
    }

    /// Get available labels in current context
    public func availableLabels() -> [String] {
        Array(mapping.keys).sorted()
    }

    /// Creates a label resolver for a specific context
    /// REQUIRES: Every label must have an explicit network_public_key - no defaults allowed
    public static func createContextResolver(
        systemConfig: LabelResolverConfig,
        userProfilePublicKeys: [Data] // From request context - empty vec means no profile keys
    ) throws -> LabelResolver {
        try validate(systemConfig: systemConfig)
        var out: [String: LabelKeyInfo] = [:]
        out.reserveCapacity(systemConfig.labelMappings.count)

        for (label, value) in systemConfig.labelMappings {
            let networkKey = value.networkPublicKey
            let profileKeys: [Data]

            if let spec = value.userKeySpec {
                switch spec {
                case .currentUser:
                    profileKeys = userProfilePublicKeys
                case let .custom(name):
                    throw LabelResolverError.invalidConfiguration("Custom userKeySpec '\(name)' requires explicit pre-resolution before factory call")
                }
            } else {
                profileKeys = []
            }

            out[label] = LabelKeyInfo(
                profilePublicKeys: profileKeys,
                networkPublicKey: networkKey
            )
        }

        return LabelResolver(mapping: out)
    }
}

// MARK: - Validation Functions

private func validate(systemConfig: LabelResolverConfig) throws {
    if systemConfig.labelMappings.isEmpty {
        throw LabelResolverError.invalidConfiguration("labelMappings must not be empty")
    }

    // All labels must be unique and non-empty
    for (label, value) in systemConfig.labelMappings {
        if label.isEmpty {
            throw LabelResolverError.invalidConfiguration("Empty label name")
        }

        let hasNetwork = value.networkPublicKey != nil
        let hasUserSpec = value.userKeySpec != nil

        if !hasNetwork, !hasUserSpec {
            throw LabelResolverError.invalidConfiguration("Label '\(label)' must specify either networkPublicKey or userKeySpec (or both)")
        }

        if let net = value.networkPublicKey, net.isEmpty {
            throw LabelResolverError.invalidConfiguration("Label '\(label)' has empty networkPublicKey — use nil for profile-only labels")
        }
    }
}
