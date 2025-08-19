## Swift Serializer Alignment with Rust `runar-serializer`

This document audits the current Swift implementation in `swift-serializer/` and lists precise changes required to align 100% with the Rust crate’s external API and behavior, including the new platform‑neutral wire type names and the type‑name registry described in `TYPE_NAME_SPEC.md`.

Scope reviewed:
- Swift sources: `swift-serializer/Sources/RunarSerializer/{AnyValue.swift, EncryptedPropertyWrapper.swift, EncryptionTypes.swift, EnvelopeEncryption.swift}` and all tests under `swift-serializer/Tests/RunarSerializerTests/`
- Rust sources: `runar-serializer/src/{arc_value.rs,registry.rs,traits.rs,lib.rs}` and tests under `runar-serializer/tests/`

The goal is to make Swift’s `AnyValue` feature‑for‑feature equivalent to Rust’s `ArcValue`, with matching binary format, lazy behavior, encryption semantics, and JSON conversion, while adopting the new wire‑name registry.

---

### 1) Wire Header and Type Name Normalization

Rust now writes a platform‑neutral wire name into the header:
- Header: `[category:u8][is_encrypted:u8][name_len:u8][name_bytes][payload]`
- For primitives: fixed wire names like `string`, `bool`, `i64`, `bytes`, etc.
- For containers: reserved names `list`, `map`, `json` (element types NOT encoded in the name).
- For structs: default to the simple ident (e.g., `User`), or an explicit override via macro attribute (e.g., `profile.User`).
- Unknown wire names must error on decode.

Findings in Swift:
- `AnyValue.serialize` writes `box.typeName` (e.g., "String", "Data", "Array<AnyValue>") into the header, not normalized wire names.
- Containers write Swift type names ("Array<AnyValue>", "Dictionary<String, AnyValue>") instead of `list`/`map`.
- JSON writes type name "JSON" instead of `json`.

Required changes (Swift):
- Resolve and write the normalized wire name into the header for all categories:
  - `String` → `"string"`
  - `Bool` → `"bool"`
  - `Data` (bytes) → `"bytes"`
  - Integer/float types use exact variants: `Int8/Int16/Int32/Int64/UInt8/.../Float/Double` → `"i8"/"i16"/.../"f32"/"f64"`. Avoid ambiguous `Int`/`UInt` or map them deterministically (see §10).
  - Containers: `list`, `map`, `json`.
  - Structs: default to simple ident or macro override (see §3 and §6).

---

### 2) Payload Encoding Format (CBOR for all categories)

Rust payloads are consistently encoded with `serde_cbor` for all categories (primitives, list, map, struct, json). Containers and JSON leverage CBOR to preserve cross‑platform fidelity.

Findings in Swift:
- Primitives: CBOR via SwiftCBOR – OK.
- List: custom length‑prefixed concatenation of serialized `AnyValue` entries – NOT CBOR.
- Map: custom length‑prefixed key/value layout – NOT CBOR.
- JSON: raw JSON bytes – NOT CBOR `serde_json::Value` representation.

Required changes (Swift):
- Switch list payloads to CBOR array encoding of either:
  - `[AnyValue]` encoded as CBOR using the same header+payload per entry? Rust does NOT nest headers in CBOR; instead, the list’s CBOR payload is a `Vec<T>` or `Vec<ArcValue>` depending on creation. For cross‑SDK parity: encode the payload as CBOR array of element payloads matching the Rust shape for `Vec<ArcValue>` (i.e., the elements themselves are ArcValue/AnyValue and serialize to the same header+payload binary blocks). To align with Rust tests that decode `Vec<ArcValue>` for JSON conversion, the Swift list serialization should CBOR‑encode the element sequence where each element is an `AnyValue` serialized buffer.
- Switch map payloads to CBOR map encoding using the same approach (`HashMap<String, ArcValue>` parity).
- Switch JSON payloads to CBOR encoding of a JSON value (mirror `serde_json::Value`), not raw JSON text. Keep header name = `json`.

Notes:
- The Rust implementation supports generic fallbacks in JSON conversion. Matching that requires the CBOR payloads to be compatible.

---

### 3) Type‑Name Registry (wire name ↔ Swift type)

Rust defines registries to resolve between Rust type names and wire names, and to bind JSON converters by wire name. Primitives and containers are pre‑registered. Macros register struct wire names (default or override) and bind JSON conversion and decryptors.

Rust registry highlights:
```1:45:runar-rust/runar-serializer/src/registry.rs
//! Global decryptor registry used by ArcValue.
use std::any::{Any, TypeId};
...
static TYPE_NAME_RUST_TO_WIRE: Lazy<DashMap<&'static str, &'static str>> = Lazy::new(DashMap::new);
static WIRE_NAME_JSON_REGISTRY: Lazy<DashMap<&'static str, ToJsonFn>> = Lazy::new(DashMap::new);
static WIRE_NAME_TO_TYPEID: Lazy<DashMap<&'static str, TypeId>> = Lazy::new(DashMap::new);
static WIRE_NAME_TO_RUST: Lazy<DashMap<&'static str, &'static str>> = Lazy::new(DashMap::new);
```

Findings in Swift:
- `TypeRegistry` maps Swift type name strings to decode closures; it is not keyed by normalized wire name and does not store the Swift.Type mapping or JSON conversion closures by wire name.
- No pre‑registration of primitives and containers.

Required changes (Swift):
- Introduce a `TypeNameRegistry`:
  - `swiftTypeName (String) → wireName (String)`
  - `wireName (String) → jsonConverter (Data) throws -> Any` (for to‑JSON behavior)
  - `wireName (String) → Swift.Type` (for dynamic flows)
  - `wireName (String) → swiftTypeName (String)` (diagnostics)
  - Duplicate handling: first‑wins with a warning, matching Rust.
- Pre‑register all primitives and containers at init:
  - `String→"string"`, `Bool→"bool"`, `Data→"bytes"`, `Int8→"i8"`, …, `Double→"f64"`, plus container wire names `list`, `map`, `json`.
- Public API to mirror Rust:
  - `registerTypeName<T>(wireName: String)` to be called by Swift macros (Plain/Encrypt) at load time.
  - `lookupWireName(swiftTypeName: String) -> String?`
  - `lookupJsonByWireName(_ wire: String) -> ((Data) throws -> Any)?`
  - `lookupSwiftTypeByWireName(_ wire: String) -> Any.Type?`
  - `lookupSwiftNameByWireName(_ wire: String) -> String?`

---

### 4) Header Resolution on Serialize and Strict Lookup on Deserialize

Rust behavior:
- Serialize: resolve inner type to wire name via registry; containers/bytes/json use reserved names.
- Deserialize: treat header name as the wire name; for primitives, dispatch by the wire name; for containers/json, use lazy structures; unknown names → error.

Findings in Swift:
- Serialize currently writes Swift type names; decrypt recipient selection uses `resolver.resolveLabel(typeName)` which couples labels to type names.
- Deserialize interprets the header name as a Swift type name and applies ad‑hoc heuristics (e.g., `contains("Struct")`).

Required changes (Swift):
- Serialize must use wire names from the new registry.
- Deserialize must treat header name as a wire name and dispatch accordingly:
  - For primitives: decode by fixed wire names table.
  - For `bytes`: CBOR byte string.
  - For containers/json: construct lazy structures and use wire‑name keyed JSON converters.
- Remove all heuristics using Swift display type names.

---

### 5) Lazy Deserialization Semantics and Zero‑Copy

Rust:
- Keeps the original buffer (`Arc<[u8]>`) and slice offsets in `LazyDataWithOffset` to avoid copies.
- On access, decrypts if needed, then CBOR‑decodes to the requested type, with fallbacks and registry integration.

Findings in Swift:
- `LazyData` stores a `Data` copy of the payload rather than the full original buffer with offsets.
- Decryption path re‑wraps into a new `LazyData` with copied data.
- Access paths rely on string checks and decode to intermediate `Dictionary` for structs, not strongly‑typed decode.

Required changes (Swift):
- Store the original serialized buffer and offsets to minimize copies (mirror `LazyDataWithOffset`). Use copy‑on‑write `Data` slices when available, but ensure we do not clone unnecessarily.
- For JSON category and containers, implement the same lazy strategy: defer CBOR decode until the typed accessor or JSON conversion is invoked.
- Replace the current struct CBOR→dictionary fallback with proper type‑directed decode using registry or direct CBOR decode to `T`.

---

### 6) Macro Integration (Swift side) and Struct Wire Names

Rust macros (`Plain`, `Encrypt`) perform at load time:
- Register `to_json::<T>()` and bind it by both rust type name and wire name.
- Register decryptor (`Plain ↔ Encrypted`) for encrypted types.
- Register type wire name (default ident or `#[runar(name = "..."))`).

Findings in Swift:
- Swift macros are present, but the serializer lacks the registry to accept wire‑name registrations and to bind JSON converters by wire name.

Required changes (Swift):
- Extend Swift macros to call `registerTypeName<T>(wireName: String)` on module load.
- Bind a `toJSON` converter for `T` in the registry keyed by the wire name, mirroring Rust’s `register_to_json::<T>()`.
- Ensure duplicate wire‑name warnings are logged and first registration wins.

---

### 7) JSON Conversion Parity (`to_json()` behavior)

Rust `ArcValue::to_json()`:
- Primitives: numbers mapped precisely; 128‑bit and bytes are strings (bytes as base64 string).
- `Json` category returns stored JSON value.
- `List`/`Map`/`Struct`: prefer stored `to_json_fn` or registry wire‑name JSON converters; fallback to CBOR→JSON value.

Findings in Swift:
- No top‑level `toJSON()` on `AnyValue`. Tests focus on round‑trips via `asType`.
- No registry of JSON converters by wire name.

Required changes (Swift):
- Implement `toJSON()` on `AnyValue` mirroring Rust:
  - Primitive mappings (including base64 for bytes and stringification for 128‑bit integers if supported).
  - For containers and structs: consult registry JSON converters by wire name, fallback to CBOR→JSON where applicable.

---

### 8) Encryption Semantics and SerializationContext

Rust `ArcValue::serialize(context)` behavior:
- If `context` is present, it envelope‑encrypts the serialized payload for all categories.
- For structs created via `new_struct`, the per‑field encryption is handled by the struct’s `RunarEncrypt` implementation before envelope wrapping, leveraging provided `resolver`.
- `SerializationContext` carries `keystore`, `resolver`, `network_id`, and optional `profile_public_key` (recipient selection). It does NOT resolve labels from the type name.

Findings in Swift:
- `AnyValue.serialize(context)` envelope‑encrypts payloads when `context` is present – OK.
- It calls `ctx.keystore.encryptWithEnvelope` with `profileIds` derived from `resolver.resolveLabel(typeName)?.profileIds`, where `typeName` is the header name. This couples label resolution to type names and diverges from Rust (labels are field‑level, provided via macros in the struct’s `encrypt_with_keystore`).
- Swift `SerializationContext` uses `profileId` (string) rather than an optional public key list equivalent.

Required changes (Swift):
- Align `SerializationContext` fields with Rust: `keystore`, `resolver`, `networkId`, `profilePublicKey: Data?` (or a generic recipient key representation matching `RunarKeys`).
- Remove using the type name as a label. Field‑level encryption should be applied by the macro‑generated `Encrypted` type when serializing structs; envelope encryption remains the outer layer when a context is provided.
- Deserialization must decrypt when `is_encrypted` is set, using the provided keystore, before attempting CBOR decode for the category.

---

### 9) Error Handling and Unknown Names

Rust:
- Unknown wire names → error on deserialize.
- Bounds checks on header fields are strict.

Findings in Swift:
- Errors exist for invalid category/empty/type name length; but there is no error for unknown wire names because Swift treats names as display type names.

Required changes (Swift):
- On deserialize, if the header `name` (wire name) is not recognized for the category, return an error. For containers/json, only `list`/`map`/`json` are valid wire names.

---

### 10) Primitive Mapping Table (Swift ↔ wire)

Adopt the same table as Rust:
- `String` → `string`
- `Bool` → `bool`
- `Data` → `bytes`
- `Character` → `char`
- `Int8/Int16/Int32/Int64` → `i8/i16/i32/i64`
- `UInt8/UInt16/UInt32/UInt64` → `u8/u16/u32/u64`
- `Float` → `f32`, `Double` → `f64`

Notes:
- Swift `Int`/`UInt` are platform‑width. For cross‑platform determinism, either:
  - Disallow `Int/UInt` in public APIs and prefer explicit sizes; or
  - Normalize `Int` as `i64` and `UInt` as `u64` on 64‑bit Apple platforms, documenting the rule. Tests should fixate this mapping. [Sounds good. go ahead with  Normalize `Int` as `i64` and `UInt` as `u64` on 64‑bit Apple platforms]

- 128‑bit integers do not exist natively; if supported in Swift SDK, encode/decode as `String` or via BigInt lib consistent with the spec.
Lets go with String an developers using this can then convert the string representaqtion to a BigInt using their library of choice.

---

### 11) API Parity: Typed Accessors and No‑Copy Goals

Rust accessors:
- `as_type_ref::<T>() -> Arc<T>` lazy‑materializes on demand with decrypt fallback via registry.
- Zero‑copy for as many cases as possible; bytes and JSON prefer eager when safe.

Findings in Swift:
- `asType<T>() async throws -> T` returns a value; there is no separate ref‑returning API.
- `LazyData` uses `Data` blobs; ensure we avoid unnecessary copies and decryption only when needed.

Required changes (Swift):
- Keep `asType<T>()` but ensure backing data is lazily decoded and minimize copying by slicing the original buffer where possible.
- Provide typed accessors for lists/maps analogous to Rust (`asListRef()`, `asMapRef()`) that return `[AnyValue]` / `[String: AnyValue]` built lazily from CBOR payload, again without extra copies.

---

### 12) Tests to Mirror Rust Coverage

Add or update Swift tests to match Rust’s:
- Primitive round‑trip by wire names (including `bytes`, `char`, all ints/floats).
- Struct with default wire name and with overridden name.
- Duplicate wire‑name registration warning (first‑wins).
- Containers: nested `list`/`map` with `AnyValue` elements; ensure JSON conversion parity once implemented.
- Encryption: struct field‑level via macros + outer envelope encryption; node/mobile visibility differences.
- Bounds checks on header lengths and unknown wire names.

---

### 13) File‑by‑File Swift Findings and Actions

- `AnyValue.swift`
  - Header type name must be normalized wire name, not Swift display name.
  - List/map serialization must switch from custom length‑prefix format to CBOR payloads.
  - JSON payload must be CBOR of a JSON value, not raw JSON bytes; header `json`.
  - Deserialize must treat `name` as wire name and dispatch strictly.
  - Implement `toJSON()` parity (using a registry function and CBOR fallbacks) and base64 for bytes.
  - Replace string‑based heuristics in lazy decode with wire‑name dispatch.
  - Rework `LazyData` to retain original buffer + offsets to reduce copies.

- `EncryptionTypes.swift` and `EnvelopeEncryption.swift`
  - Align `SerializationContext` fields with Rust; remove coupling of label resolution to type names.
  - Preserve outer envelope encryption behavior for all categories when context is present.

- `EncryptedPropertyWrapper.swift`
  - Property wrapper is fine; ensure macros/struct encryption use it consistently.
  - Keep using `EnvelopeEncryption` helpers; no change needed for the wrapper itself.

- Tests under `RunarSerializerTests`
  - Update binary format expectations for header names to normalized wire names.
  - Replace assumptions about list/map custom layout with CBOR expectations.
  - Add missing parity tests listed in §12.

---

### 14) Open Decisions to Close Before Implementation

- Swift `Int/UInt` mapping (§10). Recommend: map `Int`→`i64`, `UInt`→`u64` on all Apple 64‑bit targets and document this invariant; prefer explicit sizes in public models.
- 128‑bit integer support: decide on `String` or BigInt library for decode/encode; mirror JS guidance: prefer `String` in Swift for now.
- Swift JSON conversion: expose `toJSON()` API on `AnyValue` returning `Any`/`[String: Any]`/`[Any]` tree or `Foundation.JSONValue` wrapper; ensure parity with Rust output (bytes base64, 128‑bit ints as strings).

---

### 15) Summary of Breaking Changes in Swift

- Header `name` becomes normalized wire name; old Swift type names in headers are no longer valid.
- Container and JSON payloads change to CBOR.
- Deserialize rejects unknown wire names.
- New `TypeNameRegistry` with pre‑registered primitives/containers and macro‑driven registrations for structs.
- `SerializationContext` shape changes; encryption recipient selection no longer derives from type names.

These changes are required to achieve 1:1 behavior with Rust and cross‑SDK compatibility.


