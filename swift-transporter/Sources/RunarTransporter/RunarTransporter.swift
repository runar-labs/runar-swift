import Foundation
import SwiftCommon

// MARK: - Main RunarTransporter Factory

/// Main factory for creating QUIC transport instances
/// Provides a unified interface for QUIC transport protocol
/// macOS and iOS only - uses Network.framework QUIC
@available(macOS 12.0, iOS 15.0, *)
public struct RunarTransporter {
    /// Create a QUIC transport instance using Network.framework QUIC
    ///
    /// - Parameters:
    ///   - nodeInfo: Node information including ID, public key, and capabilities
    ///   - bindAddress: Address to bind to (e.g., "127.0.0.1:8080")
    ///   - messageHandler: Handler for incoming messages and peer events
    ///   - options: Transport-specific options
    ///   - logger: Logger instance for transport logging
    /// - Returns: A transport protocol instance
    @available(macOS 12.0, iOS 15.0, *)
    public static func createQuicTransport(
        nodeInfo: RunarNodeInfo,
        bindAddress: String,
        messageHandler: MessageHandlerProtocol,
        options: NetworkQuicTransportOptions,
        logger: RunarLogger
    ) -> TransportProtocol {
        NetworkQuicTransporter(
            nodeInfo: nodeInfo,
            bindAddress: bindAddress,
            messageHandler: messageHandler,
            options: options,
            logger: logger
        )
    }

    /// Create a QUIC transport with default options
    ///
    /// - Parameters:
    ///   - nodeInfo: Node information including ID, public key, and capabilities
    ///   - bindAddress: Address to bind to (e.g., "127.0.0.1:8080")
    ///   - messageHandler: Handler for incoming messages and peer events
    ///   - logger: Logger instance for transport logging
    /// - Returns: A transport protocol instance with default options
    @available(macOS 12.0, iOS 15.0, *)
    public static func createQuicTransport(
        nodeInfo: RunarNodeInfo,
        bindAddress: String,
        messageHandler: MessageHandlerProtocol,
        logger: RunarLogger
    ) -> TransportProtocol {
        createQuicTransport(
            nodeInfo: nodeInfo,
            bindAddress: bindAddress,
            messageHandler: messageHandler,
            options: NetworkQuicTransportOptions.default(),
            logger: logger
        )
    }

    /// Create a QUIC transport optimized for mobile devices
    ///
    /// - Parameters:
    ///   - nodeInfo: Node information including ID, public key, and capabilities
    ///   - bindAddress: Address to bind to (e.g., "127.0.0.1:8080")
    ///   - messageHandler: Handler for incoming messages and peer events
    ///   - logger: Logger instance for transport logging
    /// - Returns: A transport protocol instance optimized for mobile
    @available(macOS 12.0, iOS 15.0, *)
    public static func createMobileQuicTransport(
        nodeInfo: RunarNodeInfo,
        bindAddress: String,
        messageHandler: MessageHandlerProtocol,
        logger: RunarLogger
    ) -> TransportProtocol {
        createQuicTransport(
            nodeInfo: nodeInfo,
            bindAddress: bindAddress,
            messageHandler: messageHandler,
            options: NetworkQuicTransportOptions.mobileOptimized(),
            logger: logger
        )
    }

    /// Create a QUIC transport with custom certificates
    ///
    /// - Parameters:
    ///   - nodeInfo: Node information including ID, public key, and capabilities
    ///   - bindAddress: Address to bind to (e.g., "127.0.0.1:8080")
    ///   - messageHandler: Handler for incoming messages and peer events
    ///   - certificates: TLS certificates for secure connections
    ///   - secKey: SecKey reference for the private key (for SecIdentity creation)
    ///   - logger: Logger instance for transport logging
    /// - Returns: A transport protocol instance with custom certificates
    @available(macOS 12.0, iOS 15.0, *)
    public static func createSecureQuicTransport(
        nodeInfo: RunarNodeInfo,
        bindAddress: String,
        messageHandler: MessageHandlerProtocol,
        certificates: [Data],
        secKey: SecKey,
        logger: RunarLogger
    ) -> TransportProtocol {
        let options = NetworkQuicTransportOptions.withCertificates(
            certificates: certificates,
            secKey: secKey,
            mobileKeyManager: nil // Optional for convenience method
        )

        return createQuicTransport(
            nodeInfo: nodeInfo,
            bindAddress: bindAddress,
            messageHandler: messageHandler,
            options: options,
            logger: logger
        )
    }
}
