import Foundation

// TopicPath: normalized path with network id and segments
public struct TopicPath: Equatable, Hashable, Sendable {
	public let networkId: String
	public let segments: [String]
	public let isPattern: Bool

	public init(networkId: String, segments: [String]) {
		self.networkId = networkId
		self.segments = segments
		self.isPattern = segments.contains("*") || segments.contains(">") || segments.contains(where: { $0.hasPrefix("{") && $0.hasSuffix("}") })
	}

	public static func parse(_ full: String) -> TopicPath {
		let parts = full.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
		let net = parts.count > 1 ? parts[0] : "default"
		let rest = parts.count > 1 ? parts[1] : parts[0]
		let segs = rest.split(separator: "/").map(String.init)
		return TopicPath(networkId: net, segments: segs)
	}

	public func asString() -> String { "\(networkId):\(segments.joined(separator: "/"))" }
}

struct PathTrieMatch<T> {
	let content: T
	let params: [String: String]
}

final class PathTrie<T> {
	private var content: [T] = []
	private var children: [String: PathTrie<T>] = [:]
	private var wildcardChild: PathTrie<T>? // "*"
	private var templateChild: PathTrie<T>? // "{param}"
	private var templateParamName: String?
	private var multiWildcard: [T] = [] // for ">"
	private var networks: [String: PathTrie<T>] = [:]

	init() {}

	func setValue(topic: TopicPath, content value: T) {
		setValues(topic: topic, contents: [value])
	}

	func setValues(topic: TopicPath, contents values: [T]) {
		let netTrie = networks[topic.networkId] ?? PathTrie<T>()
		networks[topic.networkId] = netTrie
		netTrie.setValuesInternal(segments: topic.segments, index: 0, contents: values)
	}

	func appendValue(topic: TopicPath, content value: T) {
		let netTrie = networks[topic.networkId] ?? PathTrie<T>()
		networks[topic.networkId] = netTrie
		netTrie.appendValueInternal(segments: topic.segments, index: 0, content: value)
	}

	func remove(where predicate: (T) -> Bool, topic: TopicPath) -> Bool {
		guard let netTrie = networks[topic.networkId] else { return false }
		return netTrie.removeInternal(segments: topic.segments, index: 0, predicate: predicate)
	}

	func findMatches(topic: TopicPath) -> [PathTrieMatch<T>] {
		guard let netTrie = networks[topic.networkId] else { return [] }
		var results: [PathTrieMatch<T>] = []
		if topic.isPattern {
			netTrie.collectWildcardMatches(patternSegments: topic.segments, index: 0, results: &results)
			return results
		}
		netTrie.findMatchesInternal(segments: topic.segments, index: 0, results: &results, params: [:])
		return results
	}

	// MARK: internal
	private func setValuesInternal(segments: [String], index: Int, contents values: [T]) {
		guard index < segments.count else {
			content = values
			return
		}
		let seg = segments[index]
		if seg == ">" {
			multiWildcard.append(contentsOf: values)
			return
		} else if seg == "*" {
			if wildcardChild == nil { wildcardChild = PathTrie<T>() }
			wildcardChild?.setValuesInternal(segments: segments, index: index + 1, contents: values)
			return
		} else if seg.hasPrefix("{") && seg.hasSuffix("}") {
			if templateChild == nil { templateChild = PathTrie<T>(); templateParamName = String(seg.dropFirst().dropLast()) }
			templateChild?.setValuesInternal(segments: segments, index: index + 1, contents: values)
			return
		} else {
			let child = children[seg] ?? PathTrie<T>()
			children[seg] = child
			child.setValuesInternal(segments: segments, index: index + 1, contents: values)
		}
	}

	private func appendValueInternal(segments: [String], index: Int, content value: T) {
		guard index < segments.count else {
			content.append(value)
			return
		}
		let seg = segments[index]
		if seg == ">" {
			multiWildcard.append(value)
			return
		} else if seg == "*" {
			if wildcardChild == nil { wildcardChild = PathTrie<T>() }
			wildcardChild?.appendValueInternal(segments: segments, index: index + 1, content: value)
			return
		} else if seg.hasPrefix("{") && seg.hasSuffix("}") {
			if templateChild == nil { templateChild = PathTrie<T>(); templateParamName = String(seg.dropFirst().dropLast()) }
			templateChild?.appendValueInternal(segments: segments, index: index + 1, content: value)
			return
		} else {
			let child = children[seg] ?? PathTrie<T>()
			children[seg] = child
			child.appendValueInternal(segments: segments, index: index + 1, content: value)
		}
	}

	private func removeInternal(segments: [String], index: Int, predicate: (T) -> Bool) -> Bool {
		guard index < segments.count else {
			let original = content.count
			content.removeAll(where: predicate)
			return content.count != original
		}
		let seg = segments[index]
		if seg == ">" {
			let original = multiWildcard.count
			multiWildcard.removeAll(where: predicate)
			return multiWildcard.count != original
		} else if seg == "*" {
			return wildcardChild?.removeInternal(segments: segments, index: index + 1, predicate: predicate) ?? false
		} else if seg.hasPrefix("{") && seg.hasSuffix("}") {
			return templateChild?.removeInternal(segments: segments, index: index + 1, predicate: predicate) ?? false
		} else {
			return children[seg]?.removeInternal(segments: segments, index: index + 1, predicate: predicate) ?? false
		}
	}

	private func findMatchesInternal(segments: [String], index: Int, results: inout [PathTrieMatch<T>], params: [String: String]) {
		if index >= segments.count {
			for v in content { results.append(PathTrieMatch(content: v, params: params)) }
			for v in multiWildcard { results.append(PathTrieMatch(content: v, params: params)) }
			return
		}
		let seg = segments[index]
		// literal
		if let child = children[seg] {
			child.findMatchesInternal(segments: segments, index: index + 1, results: &results, params: params)
		}
		// template
		if let child = templateChild, let key = templateParamName {
			var next = params; next[key] = seg
			child.findMatchesInternal(segments: segments, index: index + 1, results: &results, params: next)
		}
		// wildcard
		if let child = wildcardChild {
			child.findMatchesInternal(segments: segments, index: index + 1, results: &results, params: params)
		}
		// multi wildcard at this level also applies
		for v in multiWildcard { results.append(PathTrieMatch(content: v, params: params)) }
	}

	private func collectWildcardMatches(patternSegments: [String], index: Int, results: inout [PathTrieMatch<T>]) {
		if index >= patternSegments.count {
			for v in content { results.append(PathTrieMatch(content: v, params: [:])) }
			for v in multiWildcard { results.append(PathTrieMatch(content: v, params: [:])) }
			collectAllHandlers(results: &results)
			return
		}
		let seg = patternSegments[index]
		if seg == "*" || seg == ">" {
			collectAllHandlers(results: &results)
			return
		}
		if let child = children[seg] {
			child.collectWildcardMatches(patternSegments: patternSegments, index: index + 1, results: &results)
		}
		if let child = wildcardChild {
			child.collectWildcardMatches(patternSegments: patternSegments, index: index + 1, results: &results)
		}
		if let child = templateChild {
			child.collectWildcardMatches(patternSegments: patternSegments, index: index + 1, results: &results)
		}
	}

	private func collectAllHandlers(results: inout [PathTrieMatch<T>]) {
		for v in content { results.append(PathTrieMatch(content: v, params: [:])) }
		for v in multiWildcard { results.append(PathTrieMatch(content: v, params: [:])) }
		for (_, c) in children { c.collectAllHandlers(results: &results) }
		wildcardChild?.collectAllHandlers(results: &results)
		templateChild?.collectAllHandlers(results: &results)
	}
}
