import Foundation
import SwiftCommon
import RunarSerializer

public enum ServiceState: String, Codable {
	case created
	case initialized
	case running
	case stopped
	case paused
	case error
	case unknown
}

public protocol AbstractService: AnyObject {
	var name: String { get }
	var version: String { get }
	var path: String { get }
	var description: String { get }
	var networkId: String? { get set }

	func initService(_ context: LifecycleContext) async throws
	func start(_ context: LifecycleContext) async throws
	func stop(_ context: LifecycleContext) async throws
}
