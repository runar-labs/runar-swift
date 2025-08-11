import Foundation

public final class SimulatedConnection {
    public typealias BiResponseHandler = (Data) -> Data?
    private let biResponseHandler: BiResponseHandler?

    public init(biResponseHandler: BiResponseHandler? = nil) {
        self.biResponseHandler = biResponseHandler
    }

    public func openBi() -> (SimulatedSendStream, SimulatedRecvStream) {
        let recv = SimulatedRecvStream()
        let send = SimulatedSendStream(onFinish: { sentBytes in
            if let handler = self.biResponseHandler, let resp = handler(sentBytes) {
                recv.inject(bytes: resp)
            }
        })
        return (send, recv)
    }

    public func openUni() -> SimulatedSendStream {
        SimulatedSendStream(onFinish: { _ in })
    }
}

public final class SimulatedSendStream {
    private var buffer = Data()
    private var finished = false
    private let onFinish: (Data) -> Void

    public init(onFinish: @escaping (Data) -> Void) {
        self.onFinish = onFinish
    }

    public func writeAll(_ data: Data) throws {
        guard !finished else { throw NSError(domain: "sim", code: 1) }
        buffer.append(data)
    }

    public func finish() throws {
        guard !finished else { return }
        finished = true
        onFinish(buffer)
    }
}

public final class SimulatedRecvStream {
    private var inbox = Data()

    fileprivate func inject(bytes: Data) { inbox.append(bytes) }

    /// Read one framed payload (using our 4-byte BE frame)
    public func readFrame() -> Data? {
        var buf = inbox
        let frames = Framing.decodeFrames(&buf)
        if let first = frames.first {
            inbox = buf // update remaining
            return first
        }
        return nil
    }
}


