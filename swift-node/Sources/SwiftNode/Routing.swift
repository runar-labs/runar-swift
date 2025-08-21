import Foundation
import SwiftCommon

// MARK: - Routing Module

// This file now re-exports the routing functionality from SwiftCommon
// for backward compatibility with existing code in swift-node

// Re-export TopicPath and PathTrie from SwiftCommon
public typealias TopicPath = SwiftCommon.TopicPath

// PathTrieMatch is internal to PathTrie implementation, so we don't re-export it
// Users should use the PathTrie directly
