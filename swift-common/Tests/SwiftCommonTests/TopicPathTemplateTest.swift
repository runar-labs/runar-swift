@testable import SwiftCommon
import Testing

/// Tests for topic path templates and parameter extraction
///
/// INTENTION: Verify that TopicPath template parameters are correctly handled.
@Suite("TopicPath Template Tests")
struct TopicPathTemplateTest {
    // Test matching a path against a template and extracting parameters
    @Test
    func extractParamsFromTemplate() throws {
        // A template pattern for our Registry Service paths
        let template = "services/{service_path}/state"

        // An actual path that matches the template
        let path = try TopicPath.parse("services/math/state")

        // Extract parameters from the path
        let params = path.extractParams(template)
        #expect(params?["service_path"] == "math")

        // Try another path
        let path2 = try TopicPath.parse("main:services/auth/state")
        let params2 = path2.extractParams(template)
        #expect(params2?["service_path"] == "auth")

        // A path that doesn't match the segment count
        let nonMatching1 = try TopicPath.parse("main:services/math")
        #expect(nonMatching1.extractParams(template) == nil)

        // A path that doesn't match the literal segments
        let nonMatching2 = try TopicPath.parse("main:users/math/profile")
        #expect(nonMatching2.extractParams(template) == nil)
    }

    @Test
    func testMatchesTemplate() throws {
        let template = "services/{service_path}/state"

        // Paths that should match
        let path1 = try TopicPath.parse("main:services/math/state")
        let path2 = try TopicPath.parse("main:services/auth/state")

        #expect(path1.matchesTemplate(template))
        #expect(path2.matchesTemplate(template))

        // Paths that shouldn't match
        let path3 = try TopicPath.parse("main:services/math")
        let path4 = try TopicPath.parse("main:users/auth/profile")

        #expect(!path3.matchesTemplate(template))
        #expect(!path4.matchesTemplate(template))
    }

    @Test
    func testFromTemplate() throws {
        let template = "services/{service_path}/state"

        // Create parameters
        let params = ["service_path": "math"]

        // Create a path from the template
        let path = try TopicPath.fromTemplate(template, params: params, networkId: "main")

        // Verify the created path
        #expect(path.asString() == "main:services/math/state")
        #expect(path.servicePath == "services")
        #expect(path.networkId == "main")

        // Multiple parameters test
        let template2 = "{service_type}/{service_name}/{action}"

        let params2 = [
            "service_type": "internal",
            "service_name": "registry",
            "action": "list",
        ]

        let path2 = try TopicPath.fromTemplate(template2, params: params2, networkId: "main")
        #expect(path2.asString() == "main:internal/registry/list")
    }

    @Test
    func registryServiceUseCase() throws {
        // Template for our registry service paths
        let listTemplate = "services/list"
        let serviceTemplate = "services/{service_path}"
        let stateTemplate = "services/{service_path}/state"
        let actionsTemplate = "services/{service_path}/actions"

        // Test matching for various paths
        let listPath = try TopicPath.parse("main:services/list")
        #expect(listPath.matchesTemplate(listTemplate))

        let servicePath = try TopicPath.parse("main:services/math")
        #expect(servicePath.matchesTemplate(serviceTemplate))

        let statePath = try TopicPath.parse("main:services/math/state")
        #expect(statePath.matchesTemplate(stateTemplate))

        // Create template path objects for testing matches() in both directions
        let templateTopicPath = try TopicPath.parse("main:\(serviceTemplate)")

        // A template path shouldn't match a concrete path in this direction
        #expect(!templateTopicPath.matches(servicePath))

        // But a concrete path should match a template via the matchesTemplate method
        #expect(servicePath.matchesTemplate(serviceTemplate))

        // Extract service path from a request
        let params = statePath.extractParams(stateTemplate)
        #expect(params?["service_path"] == "math")

        // Create a path for a specific service's actions
        let params2 = ["service_path": "auth"]

        let actionsPath = try TopicPath.fromTemplate(actionsTemplate, params: params2, networkId: "main")
        #expect(actionsPath.asString() == "main:services/auth/actions")
    }

    @Test
    func pathWithTemplates() throws {
        let pathStr = "main:services/{service_path}/state"
        let path = try TopicPath.parse(pathStr)

        #expect(path.hasTemplates)
        #expect(path.asString() == pathStr)

        // A path with templates is not a wildcard pattern
        #expect(!path.isPattern)
    }

    @Test
    func templatePathActionPath() throws {
        let path = try TopicPath.parse("main:services/{service_path}/actions/{action_name}")

        #expect(path.servicePath == "services")
        #expect(path.actionPath == "services/{service_path}/actions/{action_name}")

        // Test with specific values
        let params = [
            "service_path": "math",
            "action_name": "add",
        ]

        let concretePath = try TopicPath.fromTemplate(
            "services/{service_path}/actions/{action_name}",
            params: params,
            networkId: "main"
        )

        #expect(concretePath.servicePath == "services")
        #expect(concretePath.actionPath == "services/math/actions/add")
    }

    @Test
    func complexTemplateUsage() throws {
        let template = "services/{service_path}/users/{user_id}/profile"

        let params = [
            "service_path": "auth",
            "user_id": "12345",
        ]

        let path = try TopicPath.fromTemplate(template, params: params, networkId: "main")

        #expect(path.asString() == "main:services/auth/users/12345/profile")

        // Now extract params back from the path
        let extracted = path.extractParams(template)

        #expect(extracted?["service_path"] == "auth")
        #expect(extracted?["user_id"] == "12345")
    }

    @Test
    func templateEdgeCases() throws {
        // Test empty parameter name (should still work)
        let path = try TopicPath.parse("main:services/{}/state")
        #expect(path.hasTemplates)

        // Test template at beginning of path
        let path2 = try TopicPath.parse("main:{service}/actions/list")
        #expect(path2.hasTemplates)

        // Test template at end of path
        let path3 = try TopicPath.parse("main:services/actions/{name}")
        #expect(path3.hasTemplates)

        // Test multiple templates in a single path
        let path4 = try TopicPath.parse("main:{service}/{action}/{id}")
        #expect(path4.hasTemplates)

        let params = [
            "service": "auth",
            "action": "login",
            "id": "12345",
        ]

        let concrete = try TopicPath.fromTemplate("{service}/{action}/{id}", params: params, networkId: "main")

        #expect(concrete.asString() == "main:auth/login/12345")
    }

    @Test
    func serviceVersusActionTemplates() throws {
        let servicePath = try TopicPath.parse("main:services/{service_type}")
        #expect(servicePath.hasTemplates)
        #expect(servicePath.servicePath == "services")

        // Instead of using new_action_topic, create the action path manually
        let actionPathStr = "main:services/{service_type}/list"
        let actionPath = try TopicPath.parse(actionPathStr)
        #expect(actionPath.asString() == actionPathStr)
        #expect(actionPath.hasTemplates)
    }

    @Test
    func eventPathWithTemplates() throws {
        _ = try TopicPath.parse("main:services/{service_type}")

        // Instead of using new_event_topic, create the event path manually
        let eventPathStr = "main:services/{service_type}/updated"
        let eventPath = try TopicPath.parse(eventPathStr)

        #expect(eventPath.asString() == eventPathStr)
        #expect(eventPath.hasTemplates)
    }

    @Test
    func normalizedTemplateMatching() throws {
        let templatePath = try TopicPath.parse("main:services/{service_path}")
        let concretePath = try TopicPath.parse("main:services/math")

        let templateMatches = templatePath.matches(concretePath)
        let concreteMatchesTemplate = concretePath.matchesTemplate("services/{service_path}")

        // A template path shouldn't match a concrete path in this direction
        #expect(!templateMatches)

        // But a concrete path should match a template via the matchesTemplate method
        #expect(concreteMatchesTemplate)
    }

    @Test
    func registryServiceUseCaseComplex() throws {
        // Test with a real-world use case: registry service

        // Template paths for registry service
        let listServicesTemplate = "services/list"
        let serviceInfoTemplate = "services/{service_path}"
        let serviceStateTemplate = "services/{service_path}/state"

        // Create actual request paths
        let listPath = try TopicPath.parse("main:services/list")
        #expect(listPath.matchesTemplate(listServicesTemplate))

        let infoPath = try TopicPath.parse("main:services/math")
        #expect(infoPath.matchesTemplate(serviceInfoTemplate))

        let statePath = try TopicPath.parse("main:services/math/state")
        #expect(statePath.matchesTemplate(serviceStateTemplate))

        // Create template path objects for testing matches() in both directions
        let templateTopicPath = try TopicPath.parse("main:\(serviceInfoTemplate)")

        // These should match their respective templates using matchesTemplate
        #expect(listPath.matchesTemplate(listServicesTemplate))
        #expect(infoPath.matchesTemplate(serviceInfoTemplate))
        #expect(statePath.matchesTemplate(serviceStateTemplate))

        // A template path shouldn't match a concrete path in this direction
        #expect(!templateTopicPath.matches(infoPath))

        // Extract parameters
        let infoParams = infoPath.extractParams(serviceInfoTemplate)
        #expect(infoParams?["service_path"] == "math")

        let stateParams = statePath.extractParams(serviceStateTemplate)
        #expect(stateParams?["service_path"] == "math")
    }

    @Test
    func testExtractParams() throws {
        let path = try TopicPath.parse("main:services/math/state")

        // Test with a valid template
        let params = path.extractParams("services/{service_path}/state")
        #expect(params?["service_path"] == "math")

        // Test with multiple parameters
        let nestedPath = try TopicPath.parse("main:services/math/users/admin")
        let nestedParams = nestedPath.extractParams("services/{service}/users/{user_id}")
        #expect(nestedParams?["service"] == "math")
        #expect(nestedParams?["user_id"] == "admin")

        // Test with a non-matching template
        let result = path.extractParams("services/{service_path}/config")
        #expect(result == nil)

        // Test with a template that has a different segment count
        let result2 = path.extractParams("services/{service_path}")
        #expect(result2 == nil)
    }

    @Test
    func matchesTemplateComplex() throws {
        let path = try TopicPath.parse("main:services/math/state")

        // Test with matching templates
        #expect(path.matchesTemplate("services/{service_path}/state"))
        #expect(path.matchesTemplate("services/math/state"))
        #expect(path.matchesTemplate("services/{service_path}/{action}"))

        // Test with non-matching templates
        #expect(!path.matchesTemplate("services/{service_path}/config"))
        #expect(!path.matchesTemplate("users/{user_id}"))
        #expect(!path.matchesTemplate("services/{service_path}"))
        #expect(!path.matchesTemplate("services/{service_path}/state/details"))
    }

    @Test
    func fromTemplateComplex() throws {
        let params = [
            "service_path": "math",
            "action": "add",
        ]

        let path = try TopicPath.fromTemplate("services/{service_path}/{action}", params: params, networkId: "main")

        #expect(path.asString() == "main:services/math/add")
        #expect(path.servicePath == "services")
        #expect(path.networkId == "main")

        // Test with missing parameter
        #expect(throws: TopicPathError.self) {
            try TopicPath.fromTemplate("services/{service_path}/{missing_param}", params: params, networkId: "main")
        }
    }

    @Test
    func templatePathWithActionPathExtraction() throws {
        let path = try TopicPath.parse("main:services/{service_path}/actions/{action_name}")

        #expect(path.servicePath == "services")
        #expect(path.actionPath == "services/{service_path}/actions/{action_name}")

        // Test with specific values
        let params = [
            "service_path": "math",
            "action_name": "add",
        ]

        let concretePath = try TopicPath.fromTemplate(
            "services/{service_path}/actions/{action_name}",
            params: params,
            networkId: "main"
        )

        #expect(concretePath.servicePath == "services")
        #expect(concretePath.actionPath == "services/math/actions/add")
    }

    @Test
    func servicePathsVersusActionPathsWithTemplates() throws {
        let servicePath = try TopicPath.parse("main:services/{service_type}")
        #expect(servicePath.hasTemplates)
        #expect(servicePath.servicePath == "services")

        // Instead of using new_action_topic, create the action path manually
        let actionPathStr = "main:services/{service_type}/list"
        let actionPath = try TopicPath.parse(actionPathStr)
        #expect(actionPath.asString() == actionPathStr)
        #expect(actionPath.hasTemplates)
    }

    @Test
    func eventPathCreationWithTemplates() throws {
        _ = try TopicPath.parse("main:services/{service_type}")

        // Instead of using new_event_topic, create the event path manually
        let eventPathStr = "main:services/{service_type}/updated"
        let eventPath = try TopicPath.parse(eventPathStr)

        #expect(eventPath.asString() == eventPathStr)
        #expect(eventPath.hasTemplates)
    }
}
