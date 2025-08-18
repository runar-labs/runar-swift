import Foundation
import RunarSerializer

public struct RegistryServiceMetadata: Codable, Equatable {
	public let network_id: String
	public let service_path: String
	public let name: String
	public let version: String
	public let description: String
	public let registration_time: UInt64
	public let last_start_time: UInt64?

	public init(network_id: String, service_path: String, name: String, version: String, description: String, registration_time: UInt64, last_start_time: UInt64?) {
		self.network_id = network_id
		self.service_path = service_path
		self.name = name
		self.version = version
		self.description = description
		self.registration_time = registration_time
		self.last_start_time = last_start_time
	}
}
