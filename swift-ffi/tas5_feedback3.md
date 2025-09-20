[1 tool called]

Short answer: the design is fine for Swift 6; the problem is implementation patterns. Actors + async are compatible with FFI, but you must keep all unsafe pointer work in synchronous, non-escaping regions and avoid capturing the actor’s isolated state in Sendable closures or across suspension.

What to change to make it Swift 6–aligned

- Keep actor types; make APIs async, but don’t suspend inside FFI methods
  - Actor methods can be async throws but must not call await before/while handling FFI pointers. This prevents reentrancy while the actor’s `handle` is in use.

- Never capture the actor instance in closures that touch pointers
  - Pattern: copy the handle into a local constant at method start and use that. Don’t reference `self` inside any closure passed to `withUnsafeBytes` or your `withRnErrorCode`.
  - Good:
    - let handle = self.handle
    - withRnErrorCode { errPtr in rn_call(handle, ..., errPtr) }
  - Bad:
    - withRnErrorCode { errPtr in rn_call(self.handle, ..., errPtr) }  // captures actor state

- Keep all FFI calls inside non-escaping closures
  - Your `withRnErrorCode` is already non-escaping; keep it that way.
  - Use only stack locals (e.g., `var outPtr`, `var outLen`) whose addresses are passed synchronously to the C/Rust call; copy-and-free immediately after.

- Isolate raw FFI to nonisolated helpers to avoid concurrency annotations friction
  - Add internal nonisolated (free functions or static funcs) wrappers that take the raw `UnsafeMutableRawPointer` and the prepared arguments, do the `rn_*` call, and return results. Actor methods: grab local `handle`, then call the helper. This avoids capturing actor-isolated state in closures and removes Sendable pressure on closures.
  - Example shape:
    - actor method: `let handle = self.handle; return try ffi_encrypt_with_envelope(handle, ...)`
    - helper: `internal func ffi_encrypt_with_envelope(_ handle: UnsafeMutableRawPointer, ...) throws -> Data { withRnErrorCode { ... rn_fn(handle, ...) } }`

- Do not store or return unsafe pointers across actor/API boundaries
  - Continue to copy Rust buffers to Swift `Data` and free immediately (`rn_free`, `rn_string_free`).
  - Don’t embed `Unsafe*Pointer` in properties or return types.

- No @unchecked Sendable anywhere
  - Actors provide isolation; avoid making protocols Sendable. The actor type is Sendable by construction.

- No suspension while pointer is “borrowed”
  - Ensure there is no `await` between obtaining any pointer (including `withUnsafeBytes`) and finishing the FFI call + copy/free.

- Keep closures non-Sendable
  - Don’t annotate `withRnErrorCode` or `withUnsafeBytes` closures as @Sendable. They should remain non-escaping, synchronous closures.

- Optional: single-threaded executor (not required)
  - If ever needed for extremely strict threading around non-thread-safe C state, pin the actor to a serial executor. In practice, with no internal awaits, Swift will not interleave execution while the method runs.

Implementation checklist for your codebase

- Convert managers to actors and async APIs (without awaiting internally).
- In each method:
  - let handle = self.handle
  - Prepare args (build in-memory arrays of pointers/lengths)
  - Call a nonisolated helper that invokes the rn_* function inside `withRnErrorCode`
  - Immediately copy-and-free
- Ensure helpers never capture the actor or shared state; they only operate on their arguments.
- Remove all @unchecked Sendable and Sendable on protocols.

Why this addresses your Swift 6 concerns

- Actor isolation + no awaits means no reentrancy while the FFI is in progress.
- Local copies of `handle` avoid capturing isolated state in closures, so strict concurrency checks don’t complain.
- Non-escaping closures with only stack locals and copied `handle` are fully safe under Swift 6’s model.
- No Sendable hacks required.

Separate note on the CATests crash (segfault)
- Root cause: tests construct and use null/invalid raw pointers (and call FFI), which can segfault regardless of actor safety.
- Fix:
  - Do not pass hand-crafted null/fake pointers to FFI. Remove those tests or add a Swift-side nil/invalid-handle guard that throws before calling FFI. Prefer error-path tests using invalid data (empty EA keys, bad CBOR) instead.
 