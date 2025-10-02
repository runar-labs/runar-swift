@testable import SwiftCommon
import Testing

@Suite("PathTrie Tests")
struct PathTrieTest {
    @Test
    func pathTrieTemplateMatch() throws {
        let trie = PathTrie<String>()

        // Register a template pattern
        let templatePath = try TopicPath.new("services/{service_path}/state", defaultNetwork: "main")
        trie.setValue(topic: templatePath, content: "TEMPLATE")

        // Test with a matching topic
        let topic = try TopicPath.new("services/math/state", defaultNetwork: "main")
        let matches = trie.find(topic: topic)

        #expect(matches == ["TEMPLATE"])

        // Test parameter extraction
        let matchesWithParams = trie.findMatches(topic: topic)
        #expect(matchesWithParams.count == 1)
        #expect(matchesWithParams[0].content == "TEMPLATE")
        #expect(matchesWithParams[0].params["service_path"] == "math")

        // Test with a different network
        let topic2 = try TopicPath.fromFullPath("other:services/math/state")
        let matches2 = trie.find(topic: topic2)

        #expect(matches2.isEmpty)
    }

    @Test
    func pathTrieWildcardSearch() throws {
        let trie = PathTrie<String>()

        // Simple template pattern
        let pattern1 = try TopicPath.new("serviceA/action1", defaultNetwork: "main")
        trie.setValue(topic: pattern1, content: "serviceA/action1")

        // Multiple template parameters
        let pattern2 = try TopicPath.new("serviceA/action2", defaultNetwork: "main")
        trie.setValue(topic: pattern2, content: "serviceA/action2")

        // Template at beginning
        let pattern3 = try TopicPath.new("serviceA/action3", defaultNetwork: "main")
        trie.setValue(topic: pattern3, content: "serviceA/action3")

        // Template at end
        let pattern4 = try TopicPath.new("serviceB/action1", defaultNetwork: "main")
        trie.setValue(topic: pattern4, content: "serviceB/action1")

        // Template in all positions
        let pattern5 = try TopicPath.new("serviceB/action2", defaultNetwork: "main")
        trie.setValue(topic: pattern5, content: "serviceB/action2")

        // Template with different network
        let pattern6 = try TopicPath.new("serviceC/action1", defaultNetwork: "main")
        trie.setValue(topic: pattern6, content: "serviceC/action1")

        // Test basic matching
        let searchPath = try TopicPath.new("serviceA/*", defaultNetwork: "main")
        let matches = trie.find(topic: searchPath)
        #expect(matches.count == 3)
        #expect(matches.contains("serviceA/action1"))
        #expect(matches.contains("serviceA/action2"))
        #expect(matches.contains("serviceA/action3"))
    }

    @Test
    func pathTrieTemplateMatchExtended() throws {
        let trie = PathTrie<String>()

        // Simple template pattern
        let simpleTemplate = try TopicPath.new("services/{service_path}/state", defaultNetwork: "main")
        trie.setValue(topic: simpleTemplate, content: "SIMPLE_TEMPLATE")

        // Multiple template parameters
        let multiParams = try TopicPath.new("services/{service_path}/actions/{action}", defaultNetwork: "main")
        trie.setValue(topic: multiParams, content: "MULTI_PARAMS")

        // Template at beginning
        let startTemplate = try TopicPath.new("{type}/services/state", defaultNetwork: "main")
        trie.setValue(topic: startTemplate, content: "START_TEMPLATE")

        // Template at end
        let endTemplate = try TopicPath.new("services/state/{param}", defaultNetwork: "main")
        trie.setValue(topic: endTemplate, content: "END_TEMPLATE")

        // Template in all positions
        let allTemplates = try TopicPath.new("{a}/{b}/{c}", defaultNetwork: "main")
        trie.setValue(topic: allTemplates, content: "ALL_TEMPLATES")

        // Template with different network
        let diffNetwork = try TopicPath.new("services/{service_path}/state", defaultNetwork: "main")
        trie.setValue(topic: diffNetwork, content: "DIFF_NETWORK")

        // With repeated template parameter name
        let repeatedParam = try TopicPath.new("services/{param}/actions/{param}", defaultNetwork: "main")
        trie.setValue(topic: repeatedParam, content: "REPEATED_PARAM")

        // Test basic matching
        let topic1 = try TopicPath.new("services/math/state", defaultNetwork: "main")
        let matches1 = trie.find(topic: topic1)
        #expect(matches1.contains("SIMPLE_TEMPLATE"))

        // Test multiple parameters
        let topic2 = try TopicPath.new("services/math/actions/add", defaultNetwork: "main")
        let matches2 = trie.find(topic: topic2)
        #expect(matches2.contains("MULTI_PARAMS"))
        #expect(matches2.contains("REPEATED_PARAM"))

        // Test template at beginning
        let topic3 = try TopicPath.new("internal/services/state", defaultNetwork: "main")
        let matches3 = trie.find(topic: topic3)
        #expect(matches3.contains("START_TEMPLATE"))

        // Test template at end
        let topic4 = try TopicPath.new("services/state/details", defaultNetwork: "main")
        let matches4 = trie.find(topic: topic4)
        #expect(matches4.contains("END_TEMPLATE"))

        // Test all templates
        let topic5 = try TopicPath.new("x/y/z", defaultNetwork: "main")
        let matches5 = trie.find(topic: topic5)
        #expect(matches5.contains("ALL_TEMPLATES"))

        // Test network isolation
        let topic6 = try TopicPath.new("services/math/state", defaultNetwork: "main")
        let matches6 = trie.find(topic: topic6)
        #expect(matches6.contains("SIMPLE_TEMPLATE"))

        // Same path but different network - should not match
        let topic7 = try TopicPath.fromFullPath("other:services/math/state")
        let matches7 = trie.find(topic: topic7)
        #expect(matches7.isEmpty)

        // Test repeated parameter
        let topic8 = try TopicPath.new("services/param/actions/param", defaultNetwork: "main")
        let matches8 = trie.find(topic: topic8)
        #expect(matches8.contains("REPEATED_PARAM"))

        // Test parameter extraction
        let searchTopic = try TopicPath.new("services/math/state", defaultNetwork: "main")
        let matchesWithParams = trie.findMatches(topic: searchTopic)
        let simpleMatch = matchesWithParams.first { $0.content == "SIMPLE_TEMPLATE" }
        #expect(simpleMatch?.params["service_path"] == "math")
    }

    @Test
    func pathTrieWildcardMatch() throws {
        let trie = PathTrie<String>()

        // Register a wildcard pattern
        let wildcardPattern = try TopicPath.new("services/*/state", defaultNetwork: "main")
        trie.setValue(topic: wildcardPattern, content: "WILDCARD")

        // Test with a matching topic
        let topic = try TopicPath.new("services/math/state", defaultNetwork: "main")
        let matches = trie.find(topic: topic)

        #expect(matches == ["WILDCARD"])

        // Test with a different network
        let topic2 = try TopicPath.fromFullPath("other:services/math/state")
        let matches2 = trie.find(topic: topic2)

        #expect(matches2.isEmpty)
    }

    @Test
    func pathTrieWildcardMatchExtended() throws {
        let trie = PathTrie<String>()

        // Simple wildcard
        let simpleWildcard = try TopicPath.new("services/*/state", defaultNetwork: "main")
        trie.setValue(topic: simpleWildcard, content: "SIMPLE_WILDCARD")

        // Multi-segment wildcard
        let multiWildcard = try TopicPath.new("services/>", defaultNetwork: "main")
        trie.setValue(topic: multiWildcard, content: "MULTI_WILDCARD")

        // Wildcard at beginning
        let startWildcard = try TopicPath.new("*/services/state", defaultNetwork: "main")
        trie.setValue(topic: startWildcard, content: "START_WILDCARD")

        // Wildcard at end
        let endWildcard = try TopicPath.new("services/state/*", defaultNetwork: "main")
        trie.setValue(topic: endWildcard, content: "END_WILDCARD")

        // Multiple wildcards
        let multiWildcards = try TopicPath.new("services/*/actions/*", defaultNetwork: "main")
        trie.setValue(topic: multiWildcards, content: "MULTI_WILDCARDS")

        // Wildcard with different network
        let diffNetwork = try TopicPath.new("services/*/state", defaultNetwork: "main")
        trie.setValue(topic: diffNetwork, content: "DIFF_NETWORK_WILDCARD")

        // Test simple wildcard
        let topic1 = try TopicPath.new("services/math/state", defaultNetwork: "main")
        let matches1 = trie.find(topic: topic1)
        #expect(matches1.contains("SIMPLE_WILDCARD"))
        #expect(matches1.contains("MULTI_WILDCARD"))

        // Test multi-segment wildcard with different segment counts
        let topic2 = try TopicPath.new("services/math/actions/add", defaultNetwork: "main")
        let matches2 = trie.find(topic: topic2)
        #expect(matches2.contains("MULTI_WILDCARD"))
        #expect(matches2.contains("MULTI_WILDCARDS"))

        // Test wildcard at beginning
        let topic3 = try TopicPath.new("internal/services/state", defaultNetwork: "main")
        let matches3 = trie.find(topic: topic3)
        #expect(matches3.contains("START_WILDCARD"))

        // Test wildcard at end
        let topic4 = try TopicPath.new("services/state/details", defaultNetwork: "main")
        let matches4 = trie.find(topic: topic4)
        #expect(matches4.contains("END_WILDCARD"))
        #expect(matches4.contains("MULTI_WILDCARD"))

        // Test network isolation
        let topic5 = try TopicPath.new("services/math/state", defaultNetwork: "main")
        let matches5 = trie.find(topic: topic5)
        #expect(matches5.contains("SIMPLE_WILDCARD"))

        // Same path but different network - should not match
        let topic6 = try TopicPath.fromFullPath("other:services/math/state")
        let matches6 = trie.find(topic: topic6)
        #expect(matches6.isEmpty)

        // Test with many segments that should match multi-wildcard
        let topic7 = try TopicPath.new("services/a/b/c/d/e/f", defaultNetwork: "main")
        let matches7 = trie.find(topic: topic7)
        #expect(matches7.contains("MULTI_WILDCARD"))
    }

    @Test
    func pathTrieCombinedTemplateAndWildcard() throws {
        let trie = PathTrie<String>()

        // Template + wildcard
        let templateThenWildcard = try TopicPath.new("services/{service_path}/*/details", defaultNetwork: "main")
        trie.setValue(topic: templateThenWildcard, content: "TEMPLATE_THEN_WILDCARD")

        // Wildcard + template
        let wildcardThenTemplate = try TopicPath.new("services/*/actions/{action}", defaultNetwork: "main")
        trie.setValue(topic: wildcardThenTemplate, content: "WILDCARD_THEN_TEMPLATE")

        // Template + multi-wildcard
        let templateThenMulti = try TopicPath.new("services/{service_path}/>", defaultNetwork: "main")
        trie.setValue(topic: templateThenMulti, content: "TEMPLATE_THEN_MULTI")

        // Multi-wildcard at end with template earlier
        let multiThenTemplate = try TopicPath.new("{type}/services/>", defaultNetwork: "main")
        trie.setValue(topic: multiThenTemplate, content: "MULTI_THEN_TEMPLATE")

        // Complex mix of templates and wildcards
        let complexMix = try TopicPath.new("{type}/*/services/{name}/actions/*", defaultNetwork: "main")
        trie.setValue(topic: complexMix, content: "COMPLEX_MIX")

        // Different network with same pattern
        let differentNetwork = try TopicPath.new("services/{service_path}/*/details", defaultNetwork: "main")
        trie.setValue(topic: differentNetwork, content: "DIFFERENT_NETWORK")

        // Test template then wildcard
        let topic1 = try TopicPath.new("services/math/state/details", defaultNetwork: "main")
        let matches1 = trie.find(topic: topic1)
        #expect(matches1.contains("TEMPLATE_THEN_WILDCARD"))
        #expect(matches1.contains("TEMPLATE_THEN_MULTI"))

        // Test wildcard then template
        let topic2 = try TopicPath.new("services/math/actions/login", defaultNetwork: "main")
        let matches2 = trie.find(topic: topic2)
        #expect(matches2.contains("WILDCARD_THEN_TEMPLATE"))
        #expect(matches2.contains("TEMPLATE_THEN_MULTI"))

        // Test template then multi-wildcard with deep path
        let topic3 = try TopicPath.new("services/math/a/b/c/d/e", defaultNetwork: "main")
        let matches3 = trie.find(topic: topic3)
        #expect(matches3.contains("TEMPLATE_THEN_MULTI"))

        // Test multi-wildcard then template
        let topic4 = try TopicPath.new("internal/services/math/actions/anything", defaultNetwork: "main")
        let matches4 = trie.find(topic: topic4)
        #expect(matches4.contains("MULTI_THEN_TEMPLATE"))

        // Test complex mix
        let topic5 = try TopicPath.new("internal/any/services/auth/actions/login", defaultNetwork: "main")
        let matches5 = trie.find(topic: topic5)
        #expect(matches5.contains("COMPLEX_MIX"))

        // Test network isolation
        let topic6 = try TopicPath.new("services/math/state/details", defaultNetwork: "main")
        let matches6 = trie.find(topic: topic6)
        #expect(matches6.contains("TEMPLATE_THEN_WILDCARD"))

        // Test wrong network
        let topic7 = try TopicPath.fromFullPath("other:services/math/state/details")
        let matches7 = trie.find(topic: topic7)
        #expect(matches7.isEmpty)
    }

    @Test
    func pathTrieWildcardSearchIntermediateNodes() throws {
        let trie = PathTrie<String>()

        // Simulate the users_db service with actions at different levels
        // This replicates the actual bug where replication/get_table_events is not found

        // Action at root level
        let rootAction = try TopicPath.new("users_db/execute_query", defaultNetwork: "main")
        trie.setValue(topic: rootAction, content: "users_db/execute_query")

        // Action at intermediate level (replication/get_table_events)
        let intermediateAction = try TopicPath.new("users_db/replication/get_table_events", defaultNetwork: "main")
        trie.setValue(topic: intermediateAction, content: "users_db/replication/get_table_events")

        // Test wildcard search that should find ALL actions for the service
        let searchPath = try TopicPath.new("users_db/*", defaultNetwork: "main")
        let matches = trie.find(topic: searchPath)

        // This should return BOTH actions, but currently only returns execute_query
        // because replication/get_table_events is not a leaf node in the trie structure
        #expect(matches.count == 2)
        #expect(matches.contains("users_db/execute_query"))
        #expect(matches.contains("users_db/replication/get_table_events"))

        // Also test with multi-wildcard to be thorough
        let searchPathMulti = try TopicPath.new("users_db/>", defaultNetwork: "main")
        let matchesMulti = trie.find(topic: searchPathMulti)

        #expect(matchesMulti.count == 2)
        #expect(matchesMulti.contains("users_db/execute_query"))
        #expect(matchesMulti.contains("users_db/replication/get_table_events"))
    }

    @Test
    func pathTrieWildcardSearchDeepIntermediateNodes() throws {
        let trie = PathTrie<String>()

        // More complex case with deeper intermediate nodes
        let action1 = try TopicPath.new("serviceA/action1", defaultNetwork: "main")
        trie.setValue(topic: action1, content: "serviceA/action1")

        let action2 = try TopicPath.new("serviceA/replication/events/get_table_events", defaultNetwork: "main")
        trie.setValue(topic: action2, content: "serviceA/replication/events/get_table_events")

        let action3 = try TopicPath.new("serviceA/replication/events/get_table_state", defaultNetwork: "main")
        trie.setValue(topic: action3, content: "serviceA/replication/events/get_table_state")

        let action4 = try TopicPath.new("serviceA/replication/config/get_config", defaultNetwork: "main")
        trie.setValue(topic: action4, content: "serviceA/replication/config/get_config")

        // Test wildcard search
        let searchPath = try TopicPath.new("serviceA/*", defaultNetwork: "main")
        let matches = trie.find(topic: searchPath)

        // Should find action1 and all replication actions
        #expect(matches.count == 4)
        #expect(matches.contains("serviceA/action1"))
        #expect(matches.contains("serviceA/replication/events/get_table_events"))
        #expect(matches.contains("serviceA/replication/events/get_table_state"))
        #expect(matches.contains("serviceA/replication/config/get_config"))
    }

    @Test
    func pathTrieWildcardSearchMixedLevels() throws {
        let trie = PathTrie<String>()

        // Mixed levels - some at root, some at intermediate
        let queryAction = try TopicPath.new("serviceB/query", defaultNetwork: "main")
        trie.setValue(topic: queryAction, content: "serviceB/query")

        let executeAction = try TopicPath.new("serviceB/execute", defaultNetwork: "main")
        trie.setValue(topic: executeAction, content: "serviceB/execute")

        let syncAction = try TopicPath.new("serviceB/replication/sync", defaultNetwork: "main")
        trie.setValue(topic: syncAction, content: "serviceB/replication/sync")

        let eventsAction = try TopicPath.new("serviceB/replication/events", defaultNetwork: "main")
        trie.setValue(topic: eventsAction, content: "serviceB/replication/events")

        let configAction = try TopicPath.new("serviceB/admin/config", defaultNetwork: "main")
        trie.setValue(topic: configAction, content: "serviceB/admin/config")

        // Test wildcard search
        let searchPath = try TopicPath.new("serviceB/*", defaultNetwork: "main")
        let matches = trie.find(topic: searchPath)

        // Should find ALL actions at all levels
        #expect(matches.count == 5)
        #expect(matches.contains("serviceB/query"))
        #expect(matches.contains("serviceB/execute"))
        #expect(matches.contains("serviceB/replication/sync"))
        #expect(matches.contains("serviceB/replication/events"))
        #expect(matches.contains("serviceB/admin/config"))
    }

    @Test
    func pathTrieNetworkIsolationComprehensive() throws {
        let trie = PathTrie<String>()

        // Add same paths with different networks
        let mathNetwork1 = try TopicPath.fromFullPath("network1:services/math/state")
        trie.setValue(topic: mathNetwork1, content: "MATH_NETWORK1")

        let mathNetwork2 = try TopicPath.fromFullPath("network2:services/math/state")
        trie.setValue(topic: mathNetwork2, content: "MATH_NETWORK2")

        let authNetwork1 = try TopicPath.fromFullPath("network1:services/auth/state")
        trie.setValue(topic: authNetwork1, content: "AUTH_NETWORK1")

        let authNetwork2 = try TopicPath.fromFullPath("network2:services/auth/state")
        trie.setValue(topic: authNetwork2, content: "AUTH_NETWORK2")

        // Add template paths with different networks
        let eventsTemplate1 = try TopicPath.fromFullPath("network1:services/{service}/events")
        trie.setValue(topic: eventsTemplate1, content: "EVENTS_TEMPLATE_NETWORK1")

        let eventsTemplate2 = try TopicPath.fromFullPath("network2:services/{service}/events")
        trie.setValue(topic: eventsTemplate2, content: "EVENTS_TEMPLATE_NETWORK2")

        // Add wildcard paths with different networks
        let configWildcard1 = try TopicPath.fromFullPath("network1:services/*/config")
        trie.setValue(topic: configWildcard1, content: "CONFIG_WILDCARD_NETWORK1")

        let configWildcard2 = try TopicPath.fromFullPath("network2:services/*/config")
        trie.setValue(topic: configWildcard2, content: "CONFIG_WILDCARD_NETWORK2")

        // Test exact path matching with network isolation
        let topic1 = try TopicPath.fromFullPath("network1:services/math/state")
        let matches1 = trie.find(topic: topic1)
        #expect(matches1 == ["MATH_NETWORK1"])

        let topic2 = try TopicPath.fromFullPath("network2:services/math/state")
        let matches2 = trie.find(topic: topic2)
        #expect(matches2 == ["MATH_NETWORK2"])

        // Test template matching with network isolation
        let topic3 = try TopicPath.fromFullPath("network1:services/math/events")
        let matches3 = trie.find(topic: topic3)
        #expect(matches3 == ["EVENTS_TEMPLATE_NETWORK1"])

        let topic4 = try TopicPath.fromFullPath("network2:services/math/events")
        let matches4 = trie.find(topic: topic4)
        #expect(matches4 == ["EVENTS_TEMPLATE_NETWORK2"])

        // Test wildcard matching with network isolation
        let topic5 = try TopicPath.fromFullPath("network1:services/math/config")
        let matches5 = trie.find(topic: topic5)
        #expect(matches5 == ["CONFIG_WILDCARD_NETWORK1"])

        let topic6 = try TopicPath.fromFullPath("network2:services/math/config")
        let matches6 = trie.find(topic: topic6)
        #expect(matches6 == ["CONFIG_WILDCARD_NETWORK2"])

        // Test non-existent network
        let topic7 = try TopicPath.fromFullPath("network3:services/math/state")
        let matches7 = trie.find(topic: topic7)
        #expect(matches7.isEmpty)
    }

    @Test
    func pathTrieCrossNetworkSearch() throws {
        // This test verifies the behavior of findMatches when searching across networks
        let trie = PathTrie<String>()

        // Add handlers for different networks
        let mathNetwork1 = try TopicPath.fromFullPath("network1:services/math/state")
        trie.setValue(topic: mathNetwork1, content: "MATH_NETWORK1")

        let mathNetwork2 = try TopicPath.fromFullPath("network2:services/math/state")
        trie.setValue(topic: mathNetwork2, content: "MATH_NETWORK2")

        let eventsWildcard1 = try TopicPath.fromFullPath("network1:services/*/events")
        trie.setValue(topic: eventsWildcard1, content: "EVENTS_WILDCARD_NETWORK1")

        let configTemplate2 = try TopicPath.fromFullPath("network2:services/{service}/config")
        trie.setValue(topic: configTemplate2, content: "CONFIG_TEMPLATE_NETWORK2")

        // Test that findMatches only returns matches for the specific network
        let topic1 = try TopicPath.fromFullPath("network1:services/math/state")
        let matches1 = trie.findMatches(topic: topic1)
        #expect(matches1.count == 1)
        #expect(matches1[0].content == "MATH_NETWORK1")

        let topic2 = try TopicPath.fromFullPath("network2:services/math/state")
        let matches2 = trie.findMatches(topic: topic2)
        #expect(matches2.count == 1)
        #expect(matches2[0].content == "MATH_NETWORK2")

        // Test wildcard matching with network isolation
        let topic3 = try TopicPath.fromFullPath("network1:services/math/events")
        let matches3 = trie.findMatches(topic: topic3)
        #expect(matches3.count == 1)
        #expect(matches3[0].content == "EVENTS_WILDCARD_NETWORK1")

        // Test template matching with parameter extraction
        let topic4 = try TopicPath.fromFullPath("network2:services/math/config")
        let matches4 = trie.findMatches(topic: topic4)
        #expect(matches4.count == 1)
        #expect(matches4[0].content == "CONFIG_TEMPLATE_NETWORK2")
        #expect(matches4[0].params["service"] == "math")

        // Test non-existent network
        let topic5 = try TopicPath.fromFullPath("network3:services/math/state")
        let matches5 = trie.findMatches(topic: topic5)
        #expect(matches5.count == 0)
    }
}
