import Foundation
import Network
import SwiftCommon

@available(macOS 12.0, iOS 15.0, *)
public class StreamPool {
    private let logger: RunarLogger
    // For now, just a stub. In the future, can manage idle NWConnections or streams.
    public init(logger: RunarLogger) {
        self.logger = logger
    }
}
