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

    /// Add handlers for a vector of topic paths (matches Rust add_batch_values)
    public func addBatchValues(topics: [TopicPath], contents: [T]) {
        for topic in topics {
            setValues(topic: topic, contents: contents)
        }
    }

    /// Find all handlers that match a wildcard topic pattern (matches Rust find_wildcard_matches)
    public func findWildcardMatches(pattern: TopicPath) -> [PathTrieMatch<T>] {
        let networkId = pattern.networkId
        
        guard let netTrie = networks[networkId] else { return [] }
        
        return netTrie.findWildcardMatchesInternal(segments: pattern.segments.map { $0.asString() }, index: 0)
    }

    /// Remove handlers that match a predicate for a specific topic path (matches Rust remove_handler)
    public func removeHandler(topic: TopicPath, predicate: (T) -> Bool) -> Bool {
        let networkId = topic.networkId
        
        guard let netTrie = networks[networkId] else { return false }
        
        return netTrie.removeHandlerInternal(segments: topic.segments.map { $0.asString() }, index: 0, predicate: predicate)
    }

    /// Check if this trie is empty (matches Rust is_empty)
    public var isEmpty: Bool {
        content.isEmpty
            && multiWildcard.isEmpty
            && children.isEmpty
            && wildcardChild == nil
            && templateChild == nil
            && networks.isEmpty
    }

    /// Get the total number of handlers in the trie (matches Rust handler_count)
    public var handlerCount: Int {
        var count = 0
        for networkTrie in networks.values {
            count += networkTrie.countAllValues()
        }
        return count
    }

    /// Get all values from all networks (matches Rust get_all_values)
    public func getAllValues() -> [T] {
        var results: [T] = []
        for networkTrie in networks.values {
            networkTrie.collectAllValuesInternal(&results)
        }
        return results
    }

    /// Internal method to collect all values from this trie and its children (matches Rust collect_all_values_internal)
    private func collectAllValuesInternal(_ results: inout [T]) {
        // Add content from this node
        results.append(contentsOf: content)
        results.append(contentsOf: multiWildcard)

        // Recursively collect from children
        for child in children.values {
            child.collectAllValuesInternal(&results)
        }

        if let wildcard = wildcardChild {
            wildcard.collectAllValuesInternal(&results)
        }

        if let template = templateChild {
            template.collectAllValuesInternal(&results)
        }
    }

    /// Remove all values for a specific topic path (matches Rust remove_values)
    public func removeValues(topic: TopicPath) {
        let networkId = topic.networkId
        
        // Get or create network-specific trie
        let networkTrie = networks[networkId] ?? PathTrie<T>()
        networks[networkId] = networkTrie
        
        // Remove from the network-specific trie
        networkTrie.removeValuesInternal(segments: topic.segments.map { $0.asString() }, index: 0)
    }

    /// Internal recursive implementation of remove (matches Rust remove_values_internal)
    private func removeValuesInternal(segments: [String], index: Int) {
        if index >= segments.count {
            // We've reached the end of the path, remove handlers here
            content.removeAll()
            return
        }

        let segment = segments[index]

        if segment == "*" {
            // Single wildcard - remove from wildcard child
            wildcardChild?.removeValuesInternal(segments: segments, index: index + 1)
        } else if segment.hasPrefix("{"), segment.hasSuffix("}") {
            // Template parameter - remove from template child
            templateChild?.removeValuesInternal(segments: segments, index: index + 1)
        } else {
            // Literal segment - remove from child
            children[segment]?.removeValuesInternal(segments: segments, index: index + 1)
        }
    }

    /// Internal method to find wildcard matches with parameters (matches Rust find_wildcard_matches_internal)
    private func findWildcardMatchesInternal(segments: [String], index: Int) -> [PathTrieMatch<T>] {
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
                results.append(contentsOf: child.findWildcardMatchesInternal(segments: segments, index: index + 1))
            }
        }
        
        return results
    }

    /// Internal method to remove handlers matching a predicate (matches Rust remove_handler_internal)
    private func removeHandlerInternal(segments: [String], index: Int, predicate: (T) -> Bool) -> Bool {
        if index >= segments.count {
            // We've reached the end of the path, remove matching handlers here
            let originalCount = content.count
            content.removeAll { predicate($0) }
            return content.count != originalCount
        }
        
        let segment = segments[index]
        
        if segment == "*" {
            // Single wildcard - remove from wildcard child
            return wildcardChild?.removeHandlerInternal(segments: segments, index: index + 1, predicate: predicate) ?? false
        } else if segment.hasPrefix("{"), segment.hasSuffix("}") {
            // Template parameter - remove from template child
            return templateChild?.removeHandlerInternal(segments: segments, index: index + 1, predicate: predicate) ?? false
        } else {
            // Literal segment - remove from child
            return children[segment]?.removeHandlerInternal(segments: segments, index: index + 1, predicate: predicate) ?? false
        }
    }

    /// Internal method to count all values in this trie and its children
    private func countAllValues() -> Int {
        var count = content.count + multiWildcard.count
        
        // Recursively count from children
        for child in children.values {
            count += child.countAllValues()
        }
        
        if let wildcard = wildcardChild {
            count += wildcard.countAllValues()
        }
        
        if let template = templateChild {
            count += template.countAllValues()
        }
        
        return count
    }
}
