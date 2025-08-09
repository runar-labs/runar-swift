import XCTest
import SwiftCommon
@testable import RunarTransporter

@available(macOS 12.0, iOS 15.0, *)
final class SimpleConnectionTest: XCTestCase {
    
    private var transport1: NetworkQuicTransporter!
    private var transport2: NetworkQuicTransporter!
    private var logger: RunarLogger!
    
    override func setUp() async throws {
        logger = RunarLogger(subsystem: "com.runar.transporter.test", category: "SimpleConnectionTest")
        
        // Create simple message handlers
        let handler1 = TestMessageHandler { message in
            self.logger.info("Transport1 received: \(message.messageType)")
        }
        
        let handler2 = TestMessageHandler { message in
            self.logger.info("Transport2 received: \(message.messageType)")
        }
        
        // Create node info for both transports
        let node1Info = RunarNodeInfo(
            nodePublicKey: "node1-public-key".data(using: .utf8)!,
            addresses: ["127.0.0.1:50069"],
            services: []
        )
        
        let node2Info = RunarNodeInfo(
            nodePublicKey: "node2-public-key".data(using: .utf8)!,
            addresses: ["127.0.0.1:50070"],
            services: []
        )
        
        // Create transport options
        let options1 = NetworkQuicTransportOptions()
        let options2 = NetworkQuicTransportOptions()
        
        // Initialize transports
        transport1 = NetworkQuicTransporter(
            nodeInfo: node1Info,
            bindAddress: "127.0.0.1:50069",
            messageHandler: handler1,
            options: options1,
            logger: logger
        )
        
        transport2 = NetworkQuicTransporter(
            nodeInfo: node2Info,
            bindAddress: "127.0.0.1:50070",
            messageHandler: handler2,
            options: options2,
            logger: logger
        )
    }
    
    override func tearDown() async throws {
        await transport1?.stop()
        await transport2?.stop()
        transport1 = nil
        transport2 = nil
    }
    
    func testSimpleConnection() async throws {
        do {
            try await runWithTimeout(10) {
                self.logger.info("🚀 Starting simple connection test")
                
                // Step 1: Start both transports
                self.logger.info("📡 Starting transport services...")
                try await self.transport1.start()
                self.logger.info("✅ Transport1 started")
                try await self.transport2.start()
                self.logger.info("✅ Transport2 started")
                
                // Allow transports to initialize
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms
                self.logger.info("⏰ After initialization delay")
                
                // Step 2: Try to connect transport1 to transport2
                self.logger.info("🔗 Connecting transport1 to transport2...")
                
                let peer2Info = RunarPeerInfo(
                    publicKey: "node2-public-key".data(using: .utf8)!,
                    addresses: ["127.0.0.1:50070"]
                )
                
                do {
                    self.logger.info("🔗 Attempting connection...")
                    try await self.transport1.connect(to: peer2Info)
                    self.logger.info("✅ Connection attempt completed")
                } catch {
                    self.logger.error("❌ Connection failed: \(error)")
                    // Now fail the test to see what's happening
                    XCTFail("Connection failed: \(error)")
                }
                
                // Step 3: Check connection status
                let isConnected = await self.transport1.isConnected(to: "node2-test")
                self.logger.info("🔍 Connection status: \(isConnected)")
                
                // Actually verify the connection worked
                XCTAssertTrue(isConnected, "Connection should be established")
            }
        } catch {
            XCTFail("Test failed or timed out: \(error)")
        }
    }
}

// MARK: - Test Message Handler

@available(macOS 12.0, iOS 15.0, *)
private class TestMessageHandler: MessageHandlerProtocol {
    private let messageCallback: (RunarNetworkMessage) -> Void
    
    init(messageCallback: @escaping (RunarNetworkMessage) -> Void) {
        self.messageCallback = messageCallback
    }
    
    func handleMessage(_ message: RunarNetworkMessage) {
        messageCallback(message)
    }
    
    func peerConnected(_ peerInfo: RunarNodeInfo) {
        // Track peer connections if needed
    }
    
    func peerDisconnected(_ peerId: String) {
        // Track peer disconnections if needed
    }
}

 