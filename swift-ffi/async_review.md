
Yes. The same concurrency and boundary principles apply at Swift↔FFI edges. Key places to review and, if needed, adopt the async-handler pattern and Sendable-safe dispatch:

- swift-ffi
  - FFITransport.pollEvent → SwiftNode handler: already refactored to an async handler, removing non-Sendable Task capture.
  - FFIKeyStore encrypt/decrypt callbacks: OK; synchronous FFI calls returning Data. Ensure no escaping closures capture non-Sendable state.
  - FFIDiscovery event binding: emits only through transport events; no direct callbacks into Swift.

- swift-node
  - SwiftNode.handleTransportEvent: now async and awaited from the poll loop (done).
  - Event delivery: EventHandler marked @Sendable; we await handlers in an async context (done).
  - Internal Task usage: PeerConnected registry query now awaited inline (done). Avoid ad-hoc Task captures elsewhere.

- swift-serializer
  - AnyValue.deserialize: simplified deserialization with clean CBOR decoding; no complex element-level decryption needed.

- swift-test-utils
  - Fixtures are synchronous (building CBOR, setting keys); no concurrency surfaces.

Given that, the main concurrency boundary was SwiftNode’s event loop, which we’ve fixed. I also ensured SwiftNode sets an empty label resolver mapping during startup so FFI transport starts cleanly. All swift-ffi tests pass; swift-node tests pass except the new NetworkTests which needed a certificate. I’ve now added mapping; failure is due to missing node certificate in that test. We should either:
- use TestFixtures.createCAAndNodes for that test (recommended), or
- install a test certificate before starting transports.

If you want, I’ll switch NetworkTests to use fixtures so it passes consistently.