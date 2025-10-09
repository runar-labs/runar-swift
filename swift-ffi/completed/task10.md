there shuold be no use of @unchecked Sendable anywhere in the FFI code. that is a code smell.

current we have:
public class QuicTransport: @unchecked Sendable {
struct SendableHandle: @unchecked Sendable {
public class DiscoveryHandle: @unchecked Sendable {

GOAL #1 - DO an in depth detailed systematic methodicaly analisys (check all the related code in detail line by line) to undertand its use - and to provide alternative ro properly handle this.
We need a robust solution that does not use @unchecked - we have solved this for other types int eh FFI package. so check how those are handled.. CA node and etc.


GOAL #2 - Implement the selected design  - implement robust solutions. n0o hacks. no shortcuts. like @unchecked . must be robust and folow swift 6 best practices.

NO BACKWARED COMPATIBILITUY. this is full complewte refactory. this is a new codebase. no legacy code. keep code clean and aligned with final design.
 

## FINAL ROBUST DESIGN (Swift 6, zero `@unchecked`)

### 0) Non-goals and constraints

- No use of `@unchecked Sendable` anywhere.
- No passing of `UnsafeMutableRawPointer` (or any non-Sendable) across actor boundaries.
- No fallback behaviors; deterministic ownership and deallocation.
- All FFI calls remain synchronous; isolation is enforced by actors and explicit handoff protocol.

### 1) Inventory and current problems (from codebase)

- `struct SendableHandle: @unchecked Sendable` (wrapper around `UnsafeMutableRawPointer`).
- `public class DiscoveryHandle: @unchecked Sendable` holding a raw handle.
- `public class QuicTransport: @unchecked Sendable` holding a raw handle.
- `public final class CAClient: Sendable` indirectly using `SendableHandle`.
- Factory methods in `NodeKeyManager` return these wrappers constructed with raw handles, triggering “Sending '...Handle' risks causing data races”.

Root cause: creation sites “send” a non-Sendable raw pointer to another concurrency domain (a new actor or class meant to be actor-like), which violates Swift 6 Sendable rules.

### 2) Core design: Tokenized handle handoff via a global registry

To avoid sending non-Sendable pointers across actors, we introduce a thread-safe, synchronous `HandleRegistry` that mediates ownership transfer using opaque tokens:

- `HandleToken`: a `UUID` (or `UInt64` nonce) which is `Sendable`.
- `HandleRegistry`: a static, lock-protected mapping from `HandleToken` → `UnsafeMutableRawPointer` plus a `HandleKind` enum (transport, discovery, caClient, etc.) for validation.
- API (all synchronous, nonisolated, lock-protected):
  - `insert(kind: HandleKind, pointer: UnsafeMutableRawPointer) -> HandleToken` (moves ownership into registry)
  - `claim(kind: HandleKind, token: HandleToken) -> UnsafeMutableRawPointer` (atomically removes and returns; single-use)
  - `revokeIfPresent(token:)` (best-effort cleanup on failures)

Properties:
- No actor hop is required to call registry; it is synchronous and thread-safe via `os_unfair_lock` or `ManagedCriticalState`.
- The raw pointer never crosses an actor boundary as a parameter or return value; only the token does, which is Sendable.
- Ownership is linear: exactly one insertion, exactly one claim.

### 3) Actor conversions and state

- Convert raw-handle wrappers to actors:
  - `public actor QuicTransport { private let handle: UnsafeMutableRawPointer }`
  - `public actor DiscoveryHandle { private let handle: UnsafeMutableRawPointer }`
  - `public actor CAClient { private let handle: UnsafeMutableRawPointer }`
- Remove `SendableHandle` entirely. Actors are references that are Sendable-by-reference; their isolated state does not need to be Sendable.
- `NodeKeyManager` and `MobileKeyManager` remain actors; store their raw handle as private actor state.

Deallocation:
- Use actor `deinit` to free the handle deterministically. `deinit` executes on the actor’s executor; calling FFI free is safe. Do not use `nonisolated deinit` for actors.

### 4) Factory method recipe (no raw pointer crossing)

We replace the old pattern (“create raw pointer in `NodeKeyManager`, pass it into another type’s initializer”) with a tokenized handoff:

1. In `NodeKeyManager` (actor):
   - Call FFI to create the child handle synchronously (still within `NodeKeyManager` isolation).
   - Immediately call `HandleRegistry.insert(kind:.transport, pointer: p)` to obtain a `HandleToken`.
   - Construct target actor with a token-only initializer, e.g. `QuicTransport(token: token)`.
   - Return the actor reference.

2. In `QuicTransport` (actor) initializer:
   - Synchronously call `HandleRegistry.claim(kind:.transport, token: token)` to obtain the pointer.
   - Set `self.handle` to the claimed pointer. From this point, the actor owns the handle.
   - If `claim` fails, throw a precise error. Do not continue.

Important rules:
- No function signature outside of the actor contains `UnsafeMutableRawPointer`.
- Only `HandleToken` crosses actor boundaries. Tokens are single-use.
- If actor init throws after claim, ensure the handle is freed before rethrowing to prevent leaks.

Illustrative pseudocode

```swift
// NodeKeyManager (actor)
public func createTransportHandle(optionsCbor: Data) async throws -> QuicTransport {
    let nodePtr = self.handle // actor-isolated
    let transportPtr = try ffi_create_transport(nodePtr, optionsCbor: optionsCbor)
    let token = HandleRegistry.insert(kind: .transport, pointer: transportPtr)
    return try QuicTransport(token: token)
}

// QuicTransport (actor)
public actor QuicTransport {
    private let handle: UnsafeMutableRawPointer

    public init(token: HandleToken) throws {
        let ptr = try HandleRegistry.claim(kind: .transport, token: token)
        self.handle = ptr
    }

    deinit { rn_transport_free(handle) }
}
```

Apply the same pattern to `DiscoveryHandle` and `CAClient`.

### 5) Error handling and safety

- All FFI calls must use the existing `withRnError`/`FFIError` pattern; no silent failures.
- `HandleRegistry` operations:
  - `insert` must fail if a token collision somehow occurs (practically impossible with UUID; still validate).
  - `claim` must validate `HandleKind` and absence from registry; otherwise throw a specific error (`.invalidToken`, `.kindMismatch`, `.alreadyClaimed`).
  - On `QuicTransport.init(token:)` failure after `claim`, free the pointer before rethrowing.

### 6) Lifecycle and deterministic deallocation

- Each actor holding a handle frees it in `deinit`. No shared ownership.
- If a handle must be temporarily created and not yet moved, it must either be:
  - Immediately inserted into `HandleRegistry`, or
  - Freed on all failure paths within the same scope to avoid leaks.
- Never keep a handle “unregistered” across awaits.

### 7) Concurrency invariants and do/don’t

- Do:
  - Keep all raw pointers in actor-isolated state.
  - Use tokenized handoff for cross-actor construction.
  - Keep `HandleRegistry` synchronous and lock-based, not an actor.

- Don’t:
  - Pass `UnsafeMutableRawPointer` in any public API or across actors.
  - Use `@unchecked Sendable` on any type.
  - Mark actor initializers or `deinit` as `nonisolated`.

### 8) API surface adjustments

- Replace class-based wrappers with actors for `QuicTransport`, `DiscoveryHandle`, `CAClient`.
- Remove `SendableHandle` and any `_handleWrapper` usages.
- Ensure all factory methods return actor references and accept only Sendable parameters (`Data`, simple value types, other actor references).
- Provide `static create(...) async throws -> Self` helpers on the target actors as ergonomics that internally call into `NodeKeyManager` and apply the tokenized pattern, if desired.

### 9) Migration plan

Phase A (internal refactor):
- Introduce `HandleRegistry`, add tests for linearity (insert→single-claim), kind validation, and concurrency.
- Convert `QuicTransport`, `DiscoveryHandle`, and `CAClient` to actors with token initializers.
- Update `NodeKeyManager`/`MobileKeyManager` factories to use tokenized handoff.
- Remove `SendableHandle` and replace usages with direct actor state.

Phase B (API cleanup):
- Ensure no public API mentions raw pointers.
- Keep method names the same where possible; only change construction internals.
- Mark deprecated overloads if any exist that previously accepted raw pointers (none should remain).

Phase C (verification):
- Grep/SwiftLint rule to disallow `@unchecked Sendable` in `swift-ffi`.
- Build and run all tests; add integration tests covering create→use→deinit across actors for each handle type.
- Stress test: rapid create/free cycles and concurrent create/use to validate the registry and deallocation.

### 10) Test strategy (no mocks)

- Unit tests for `HandleRegistry`:
  - Insert/claim linearity and single-use tokens.
  - Kind mismatch and invalid token errors.
  - Concurrency test with many inserts/claims.

- Integration tests for each handle actor (`CAClient`, `DiscoveryHandle`, `QuicTransport`):
  - Create via `NodeKeyManager`, perform a simple FFI operation, allow deinit, assert no leaks/crashes.
  - Cross-actor usage: call methods from different tasks/actors to ensure isolation holds.

### 11) Compliance gates

- CI rule: forbid `@unchecked Sendable` usage in `swift-ffi`.
- CI rule: forbid `UnsafeMutableRawPointer` in public signatures.
- SwiftLint + SwiftFormat after changes.

With this design, we achieve a complete removal of `@unchecked Sendable`, resolve factory method Sendable violations, and establish a deterministic, production-grade concurrency and ownership model aligned with Swift 6 and our FFI architecture.