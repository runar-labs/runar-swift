import Foundation

// MARK: - Path Matching

/// Result of a path trie match operation
public struct PathTrieMatch<T> {
    public let content: T
    public let params: [String: String]
}

/// Trie-based data structure for efficient path matching with wildcards and templates
public final class PathTrie<T> {
    private var content: [T] = []
    private var children: [String: PathTrie<T>] = [:]
    private var wildcardChild: PathTrie<T>? // "*"
    private var templateChild: PathTrie<T>? // "{param}"
    private var templateParamName: String?
    private var multiWildcard: [T] = [] // for ">"
    private var networks: [String: PathTrie<T>] = [:]

    public init() {}

    /// Set a value for a specific topic path
    public func setValue(topic: TopicPath, content value: T) {
        setValues(topic: topic, contents: [value])
    }

    /// Set multiple values for a specific topic path
    public func setValues(topic: TopicPath, contents values: [T]) {
        let netTrie = networks[topic.networkId] ?? PathTrie<T>()
        networks[topic.networkId] = netTrie
        netTrie.setValuesInternal(segments: topic.segments.map { $0.asString() }, index: 0, contents: values)
    }

    private func setValuesInternal(segments: [String], index: Int, contents values: [T]) {
        if index == segments.count {
            content.append(contentsOf: values)
            return
        }

        let segment = segments[index]

        if segment == "*" {
            if wildcardChild == nil {
                wildcardChild = PathTrie<T>()
            }
            wildcardChild!.setValuesInternal(segments: segments, index: index + 1, contents: values)
        } else if segment == ">" {
            if index == segments.count - 1 {
                multiWildcard.append(contentsOf: values)
            }
        } else if segment.hasPrefix("{") && segment.hasSuffix("}") {
            let paramName = String(segment.dropFirst().dropLast())
            if templateChild == nil {
                templateChild = PathTrie<T>()
                templateParamName = paramName
            }
            templateChild!.setValuesInternal(segments: segments, index: index + 1, contents: values)
        } else {
            if children[segment] == nil {
                children[segment] = PathTrie<T>()
            }
            children[segment]!.setValuesInternal(segments: segments, index: index + 1, contents: values)
        }
    }

    /// Find all matching values for a given topic path
    public func find(topic: TopicPath) -> [T] {
        guard let netTrie = networks[topic.networkId] else { return [] }
        return netTrie.findInternal(segments: topic.segments.map { $0.asString() }, index: 0)
    }

    /// Find all matching values with parameter extraction
    public func findMatches(topic: TopicPath) -> [PathTrieMatch<T>] {
        guard let netTrie = networks[topic.networkId] else { return [] }
        return netTrie.findMatchesInternal(segments: topic.segments.map { $0.asString() }, index: 0, params: [:])
    }

    private func findInternal(segments: [String], index: Int) -> [T] {
        if index == segments.count {
            return content
        }

        let segment = segments[index]
        var results: [T] = []

        // Try exact match first
        if let child = children[segment] {
            results.append(contentsOf: child.findInternal(segments: segments, index: index + 1))
        }

        // Try wildcard match
        if let wildcard = wildcardChild {
            results.append(contentsOf: wildcard.findInternal(segments: segments, index: index + 1))
        }

        // Try template match
        if let template = templateChild {
            results.append(contentsOf: template.findInternal(segments: segments, index: index + 1))
        }

        return results
    }

    private func findMatchesInternal(segments: [String], index: Int, params: [String: String]) -> [PathTrieMatch<T>] {
        if index == segments.count {
            return content.map { PathTrieMatch(content: $0, params: params) }
        }

        let segment = segments[index]
        var results: [PathTrieMatch<T>] = []

        // Try exact match first
        if let child = children[segment] {
            results.append(contentsOf: child.findMatchesInternal(segments: segments, index: index + 1, params: params))
        }

        // Try wildcard match
        if let wildcard = wildcardChild {
            results.append(contentsOf: wildcard.findMatchesInternal(segments: segments, index: index + 1, params: params))
        }

        // Try template match
        if let template = templateChild, let paramName = templateParamName {
            var newParams = params
            newParams[paramName] = segment
            results.append(contentsOf: template.findMatchesInternal(segments: segments, index: index + 1, params: newParams))
        }

        return results
    }

    /// Remove a specific value for a topic path
    public func remove(topic: TopicPath, content value: T) where T: Equatable {
        guard let netTrie = networks[topic.networkId] else { return }
        netTrie.removeInternal(segments: topic.segments.map { $0.asString() }, index: 0, content: value)
    }

    private func removeInternal(segments: [String], index: Int, content value: T) where T: Equatable {
        if index == segments.count {
            content.removeAll { $0 == value }
            return
        }

        let segment = segments[index]

        if segment == "*" {
            wildcardChild?.removeInternal(segments: segments, index: index + 1, content: value)
        } else if segment.hasPrefix("{") && segment.hasSuffix("}") {
            templateChild?.removeInternal(segments: segments, index: index + 1, content: value)
        } else {
            children[segment]?.removeInternal(segments: segments, index: index + 1, content: value)
        }
    }

    /// Clear all data from the trie
    public func clear() {
        content.removeAll()
        children.removeAll()
        wildcardChild = nil
        templateChild = nil
        templateParamName = nil
        multiWildcard.removeAll()
        networks.removeAll()
    }
}
