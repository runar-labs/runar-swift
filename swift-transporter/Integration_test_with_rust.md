### Best path to cross-language E2E (Swift ↔ Rust)

- Strong recommendation: keep repos separate, but support both local dev and CI.
  - Local dev: point to your existing Rust repo via env var.
  - CI: optionally add the Rust repo as a submodule for pinned reproducibility.

### What to build

- Rust side: two tiny binaries reusing existing transport code
  - quic_interop_server: listens, performs handshake, echoes request→response, accepts events.
  - quic_interop_client: connects, performs handshake, sends request, validates response, sends event.
  - CLI args: `--bind host:port` (server), `--peer host:port` (client), `--ca <file>`, `--cert <file>`, `--key <file>`, `--node-id <id>`, `--timeout <sec>`.

- Swift side: one XCTest that spawns the Rust binaries
  - Generates a CA + two node certs via existing Swift code.
  - Exports CA/leaf/key as PEM to a temp dir.
  - Scenario A: start Swift server, run Rust client (Rust→Swift).
  - Scenario B: start Rust server, run Swift client (Swift→Rust).
  - Verifies handshake, request/response, and event using CBOR + 4-byte BE framing and message types 1..7.

### Repo wiring

- No submodule required for local dev:
  - Set env var `RUNAR_RUST_DIR=/Users/rafael/dev/runar-rust`.
  - Swift test uses that path to build and run the Rust interop bins.

- Optional (recommended for CI): add submodule pinned to a commit
  - Path: `swift-transporter/interop-deps/runar-rust`
  - Script prefers `RUNAR_RUST_DIR`, falls back to the submodule.

### Scripts to add (Swift repo)

- scripts/build_rust_interop.sh
  - `set -euo pipefail`
  - Resolves rust repo dir (env var or submodule).
  - Runs `cargo build --release -p <crate>` for `quic_interop_server` and `quic_interop_client`.
  - Outputs absolute paths to built bins.

- scripts/run_cross_e2e.sh
  - Calls the Swift XCTest (filter `CrossLanguageE2ETests`), or can directly spawn both sides for quick manual checks.

### Swift XCTest outline (CrossLanguageE2ETests.swift)

- Generate CA + two leaf certs with swift-keys.
- Write `ca.pem`, `node1_cert.pem`, `node1_key.pem`, `node2_cert.pem`, `node2_key.pem`.
- Scenario A:
  - Start `NetworkQuicTransporter` on ephemeral port.
  - Spawn `quic_interop_client` with the CA + node2 cert+key and peer `localhost:<swift_port>`.
  - Assert exit code 0.
- Scenario B:
  - Spawn `quic_interop_server` with CA + node1 cert+key on ephemeral port.
  - Have Swift connect to that port and run our existing request/response and event checks.
- Ensure timeouts and clean termination.

### TLS alignment details

- Use the same CA on both sides.
- Match SNI: Swift sends DNS-safe node id as SNI host; the Rust server must accept it.
- Certificates: pass full chain as needed by rustls; Swift already handles Keychain identity.

### Submodule vs local path

- For now: do not add the submodule; use `RUNAR_RUST_DIR` and your existing local repo for speed.
- When ready for CI: add submodule and pin to a commit so CI is deterministic.

If you want, I can:
- Scaffold the two Rust interop binaries inside your Rust repo (non-invasive).
- Add the build/run scripts and a `CrossLanguageE2ETests.swift` that spawns them.
- Run the new cross-language tests locally.