# QUIC/TLS Integration Status (Network.framework)

## Goals
- End-to-end QUIC connections between peers using TLS 1.3
- Mutual authentication with our CA-signed node certificates
- No hacks: use proper identities and trust evaluation

## What’s Working
- Certificate pipeline
  - CA (mobile) creates root and CA certificates
  - Nodes generate SecKey in Keychain; CA issues leaf certs
  - Leaf EKU: serverAuth + clientAuth; SAN includes `localhost`
  - Certificates imported to Keychain with stable labels
  - SecIdentity pairs correctly with Keychain private key (validated)
- TLS configuration
  - TLS 1.3 enforced, ALPN set via `NWParameters.quic`
  - SNI set to `localhost`
  - Custom trust evaluation with our CA as anchors-only
  - Local identity configured from Keychain-backed SecIdentity
- Listener
  - `NWListener` created using `NWParameters.quic` with TLS options
  - New inbound connections are accepted and started; states logged

## Current Issue
- Outbound `NWConnection` remains in `.preparing` and times out
- Inbound connection also sits in `.preparing`
- TLS verify block is not invoked on the client path
- Indicates handshake is not beginning (not a trust failure)

## Hypotheses Considered
- Identity/Keychain pairing: verified OK (private key available)
- ALPN mismatch: added `h3` in addition to `runar`
- Interface/pathing: constrained to loopback, no P2P
- IPv4 vs IPv6: likely mismatch when using `localhost`
- Policy override: removed Basic X.509 override to keep TLS policy

## Next Steps (Action Plan)
1. Force IPv4 on connect path (use `127.0.0.1` for endpoints) to avoid IPv6 ::1 binding mismatch.
2. Open a real stream immediately after start to kick QUIC state machine (already added a handshake kick send).
3. Add QUIC/TLS handshake instrumentation via connection state and verify blocks (already logging).
4. If still stuck, align listener and client parameters exactly and reduce customizations (minimal parameters + identities + anchors-only verify).
5. As a diagnostic last resort, temporarily relax verify block to confirm handshake initiation, then re-tighten.

## Out-of-Scope (kept correct but not root cause)
- Certificate generation, EKU/SANs
- Trust anchor configuration
- Keychain persistence

## Owner Notes
- The symptom (persistent `.preparing`) typically points to route/family mismatch or QUIC stack not initiating handshake frames; step (1) is the highest ROI. 