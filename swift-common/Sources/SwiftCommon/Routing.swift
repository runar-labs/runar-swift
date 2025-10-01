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
        handleSegment(segment, segments: segments, index: index, values: values)
    }

    private func handleSegment(_ segment: String, segments: [String], index: Int, values: [T]) {
        if segment == "*" {
            handleWildcardSegment(segments: segments, index: index, values: values)
        } else if segment == ">" {
            handleMultiWildcardSegment(segment: segment, segments: segments, index: index, values: values)
        } else if segment.hasPrefix("{"), segment.hasSuffix("}") {
            handleTemplateSegment(segments: segments, index: index, values: values)
        } else {
            handleLiteralSegment(segment: segment, segments: segments, index: index, values: values)
        }
    }

    private func handleWildcardSegment(segments: [String], index: Int, values: [T]) {
        if wildcardChild == nil {
            wildcardChild = PathTrie<T>()
        }
        wildcardChild?.setValuesInternal(segments: segments, index: index + 1, contents: values)
    }

    private func handleMultiWildcardSegment(segment _: String, segments: [String], index: Int, values: [T]) {
        if index == segments.count - 1 {
            multiWildcard.append(contentsOf: values)
        }
    }

    private func handleTemplateSegment(segments: [String], index: Int, values: [T]) {
        let paramName = String(segments[index].dropFirst().dropLast())
        if templateChild == nil {
            templateChild = PathTrie<T>()
            templateParamName = paramName
        }
        templateChild?.setValuesInternal(segments: segments, index: index + 1, contents: values)
    }

    private func handleLiteralSegment(segment: String, segments: [String], index: Int, values: [T]) {
        if children[segment] == nil {
            children[segment] = PathTrie<T>()
        }
        children[segment]?.setValuesInternal(segments: segments, index: index + 1, contents: values)
    }

    /// Find all matching values for a given topic path
    public func find(topic: TopicPath) -> [T] {
        guard let netTrie = networks[topic.networkId] else { return [] }

        // If the topic contains patterns, use wildcard search
        if topic.isPattern {
            return netTrie.findWildcardMatches(segments: topic.segments.map { $0.asString() }, index: 0)
        }

        return netTrie.findInternal(segments: topic.segments.map { $0.asString() }, index: 0)
    }

    /// Find all matching values with parameter extraction
    public func findMatches(topic: TopicPath) -> [PathTrieMatch<T>] {
        guard let netTrie = networks[topic.networkId] else { return [] }

        // If the topic contains patterns, use wildcard search
        if topic.isPattern {
            return netTrie.findWildcardMatchesWithParams(segments: topic.segments.map { $0.asString() }, index: 0)
        }

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

        // Try wildcard match - single wildcard matches exactly one segment
        if segment == "*" {
            // This is a search pattern, find all concrete paths at this level
            results.append(contentsOf: findAllConcretePaths())
        } else if let wildcard = wildcardChild {
            results.append(contentsOf: wildcard.findInternal(segments: segments, index: index + 1))
        }

        // Try template match
        if segment.hasPrefix("{"), segment.hasSuffix("}") {
            // This is a search pattern, find all concrete paths at this level
            results.append(contentsOf: findAllConcretePaths())
        } else if let template = templateChild {
            results.append(contentsOf: template.findInternal(segments: segments, index: index + 1))
        }

        // Try multi-wildcard match - matches zero or more segments
        if segment == ">" {
            // Multi-wildcard should match everything from here to the end
            results.append(contentsOf: findAllConcretePaths())
        }

        // Check if any stored patterns match the current search path
        results.append(contentsOf: findMatchingPatterns(for: segments, index: index))

        return results
    }

    /// Find patterns stored in this trie that match the search path
    private func findMatchingPatterns(for segments: [String], index: Int) -> [T] {
        var results: [T] = []

        // Check if any multi-wildcard patterns at this level match
        results.append(contentsOf: multiWildcard)

        // If we're at the end of the search path, check all patterns at this level
        if index == segments.count {
            return results
        }

        // Check if any wildcard patterns match
        if let wildcard = wildcardChild {
            results.append(contentsOf: wildcard.findMatchingPatterns(for: segments, index: index + 1))
        }

        // Check if any template patterns match
        if let template = templateChild {
            results.append(contentsOf: template.findMatchingPatterns(for: segments, index: index + 1))
        }

        return results
    }

    /// Recursively find all concrete values stored in this trie and its children
    private func findAllConcretePaths() -> [T] {
        var results = content // Include values at current level

        // Recursively find all values in children
        for child in children.values {
            results.append(contentsOf: child.findAllConcretePaths())
        }

        // Include wildcard child values
        if let wildcard = wildcardChild {
            results.append(contentsOf: wildcard.findAllConcretePaths())
        }

        // Include template child values
        if let template = templateChild {
            results.append(contentsOf: template.findAllConcretePaths())
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

        // Try wildcard match - single wildcard matches exactly one segment
        if segment == "*" {
            // This is a search pattern, find all concrete paths at this level
            results.append(contentsOf: findAllConcreteMatches(params: params))
        } else if let wildcard = wildcardChild {
            results.append(contentsOf: wildcard.findMatchesInternal(
                segments: segments, index: index + 1, params: params
            ))
        }

        // Try template match
        if segment.hasPrefix("{"), segment.hasSuffix("}") {
            // This is a search pattern, find all concrete paths at this level
            results.append(contentsOf: findAllConcreteMatches(params: params))
        } else if let template = templateChild, let paramName = templateParamName {
            var newParams = params
            newParams[paramName] = segment
            results.append(contentsOf: template.findMatchesInternal(
                segments: segments, index: index + 1, params: newParams
            ))
        }

        // Try multi-wildcard match - matches zero or more segments
        if segment == ">" {
            // Multi-wildcard should match everything from here to the end
            results.append(contentsOf: findAllConcreteMatches(params: params))
        }

        return results
    }

    /// Recursively find all concrete matches stored in this trie and its children
    private func findAllConcreteMatches(params: [String: String]) -> [PathTrieMatch<T>] {
        var results = content.map { PathTrieMatch(content: $0, params: params) } // Include values at current level

        // Recursively find all matches in children
        for child in children.values {
            results.append(contentsOf: child.findAllConcreteMatches(params: params))
        }

        // Include wildcard child matches
        if let wildcard = wildcardChild {
            results.append(contentsOf: wildcard.findAllConcreteMatches(params: params))
        }

        // Include template child matches
        if let template = templateChild {
            results.append(contentsOf: template.findAllConcreteMatches(params: params))
        }

        return results
    }

    /// Find all concrete values that match a wildcard pattern
    private func findWildcardMatches(segments: [String], index: Int) -> [T] {
        var results: [T] = []

        if index >= segments.count {
            // Pattern is exhausted, collect all values at this level
            collectAllConcreteValues(&results)
            return results
        }

        let segment = segments[index]

        if segment == "*" {
            // Single wildcard - collect all values from this level and below
            collectAllConcreteValues(&results)
        } else if segment == ">" {
            // Multi-wildcard - collect all values from this level and below
            collectAllConcreteValues(&results)
        } else {
            // Literal segment - only search in matching child
            if let child = children[segment] {
                results.append(contentsOf: child.findWildcardMatches(segments: segments, index: index + 1))
            }
        }

        return results
    }

    /// Find all concrete values that match a wildcard pattern with parameter extraction
    private func findWildcardMatchesWithParams(segments: [String], index: Int) -> [PathTrieMatch<T>] {
        var results: [PathTrieMatch<T>] = []

        if index >= segments.count {
            // Pattern is exhausted, collect all values at this level
            collectAllConcreteMatches(&results, params: [:])
            return results
        }

        let segment = segments[index]

        if segment == "*" {
            // Single wildcard - collect all values from this level and below
            collectAllConcreteMatches(&results, params: [:])
        } else if segment == ">" {
            // Multi-wildcard - collect all values from this level and below
            collectAllConcreteMatches(&results, params: [:])
        } else {
            // Literal segment - only search in matching child
            if let child = children[segment] {
                results.append(contentsOf: child.findWildcardMatchesWithParams(segments: segments, index: index + 1))
            }
        }

        return results
    }

    /// Collect all concrete values from this node and all children
    private func collectAllConcreteValues(_ results: inout [T]) {
        // Add values at this level
        results.append(contentsOf: content)
        results.append(contentsOf: multiWildcard)

        // Recursively collect from all children
        for child in children.values {
            child.collectAllConcreteValues(&results)
        }

        // Collect from wildcard and template children
        if let wildcard = wildcardChild {
            wildcard.collectAllConcreteValues(&results)
        }

        if let template = templateChild {
            template.collectAllConcreteValues(&results)
        }
    }

    /// Collect all concrete matches from this node and all children with parameters
    private func collectAllConcreteMatches(_ results: inout [PathTrieMatch<T>], params: [String: String]) {
        // Add matches at this level
        for value in content {
            results.append(PathTrieMatch(content: value, params: params))
        }

        for value in multiWildcard {
            results.append(PathTrieMatch(content: value, params: params))
        }

        // Recursively collect from all children
        for child in children.values {
            child.collectAllConcreteMatches(&results, params: params)
        }

        // Collect from wildcard and template children
        if let wildcard = wildcardChild {
            wildcard.collectAllConcreteMatches(&results, params: params)
        }

        if let template = templateChild {
            template.collectAllConcreteMatches(&results, params: params)
        }
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
        } else if segment.hasPrefix("{"), segment.hasSuffix("}") {
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

    /// Get all entries for a specific network
    public func getAllEntries(networkId: String) -> [T] {
        guard let netTrie = networks[networkId] else { return [] }
        return netTrie.findAllConcretePaths()
    }
}
