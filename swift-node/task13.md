GOAL ALIGN ServiceRegistry with rust

Step 1 ) remove localServicesList - this was also remove from rust.. as this was a duplicaoitn
Read the RUST code for the Service Registr in details line by line.. and comapre to teh swift implementation and make a list of all the gaps, differences,, mis aligments. CHECK EVERYRTHING do not skip anything.. make a compelte list and save to this file.

Step 2)  with the list from the prevcious step work on all items fixing one by one methodicxallt and systematical to get swigt version 100% alignement with RUST,

Step 3) lets align the swift equivalent of the rust test   /Users/rafael/dev/runar-rust/runar-node/tests/registry_service_test.rs  DO THE SAME AS Step 1 compar ethe test line by line and complie a list ofg all differences

Step 4) Fix all gaps in the test registry_service_test.rs to make teh swift 100% alIGNED TO RUST.

---------------------------------
Parity gaps vs Rust (service_registry.rs)
---------------------------------
1) Local services storage
- Swift: uses both `localServices` (PathTrie<ServiceEntry>) and `localServicesList` (ShardedConcurrentMap<TopicPath, ServiceEntry>)
- Rust: uses only `local_services` (PathTrie<Arc<ServiceEntry>>) – no extra list
- Impact: remove `localServicesList`; refactor all reads/writes to use `localServices` only

2) Get local services API
- Swift `getLocalServices()` builds a map via `localServicesList.keys()` and `.get()`
- Rust `get_local_services()` reads from trie `get_all_values()` and builds a HashMap keyed by `service_topic`
- Action: refactor Swift to use `localServices.getAllValues()` and build `[TopicPath: ServiceEntry]`

3) Register local service
- Swift `registerLocalService` inserts into `localServices` and `localServicesList`
- Rust `register_local_service` inserts only into `local_services` trie
- Action: remove insertion into `localServicesList`

4) Get all service metadata (local)
- Swift `getAllServiceMetadataRef` and `getAllLocalServiceMetadata` iterate `localServicesList`
- Rust iterates PathTrie values and derives search paths per entry
- Action: refactor both methods to iterate `localServices.getAllValues()`

5) Event publishing responsibility
- Rust explicitly states Registry should not call callbacks/handlers directly; Node is responsible
- Swift `ServiceRegistry.publish(...)` invokes handlers directly
- Action: evaluate moving publish/notification to `Node` or delegate pattern; align behavior with Rust (defer in Step 2 after storage refactor)

6) Path API types
- Rust API consistently uses `TopicPath` for registry methods
- Swift has mixed string-based variants (e.g., `registerAction(networkId:servicePath:action:...)` alongside TopicPath-based ones)
- Action: confirm final Swift surface matches Rust intent; prefer TopicPath-based APIs for registry internals (string helpers can remain as thin wrappers)

7) Remote services metadata path
- Rust `get_service_metadata` tries local first, then remote; Swift `getServiceMetadata` currently checks local only
- Action: add remote-service branch to match Rust behavior (Step 2)

8) Remote peer subscription utilities
- Rust implements full drain/paths iteration using DashMap iterators
- Swift stubs `drainRemotePeerSubscriptions` and `remoteSubscriptionPaths` return empty and log TODO
- Action: implement proper iteration helpers in `ShardedConcurrentMap` or add safe utilities to support these operations (Step 2)

9) Logging levels and messages
- Ensure Swift log levels/messages match Rust semantics (info for milestones; debug/trace otherwise)
- Action: audit and adjust after functional parity

10) Concurrency model differences (No changed needed.. swift alrady follow the proper patterns here)
- Rust uses Arc/RwLock; Swift uses @MainActor and concurrent maps. Semantics acceptable but ensure no hidden races; avoid fallbacks
- Action: maintain deterministic state transitions as in Rust’s validators

Step 1 execution plan
- Remove `localServicesList` declaration, initialization, and all usages
- Refactor: `registerLocalService`, `getLocalServices`, `getAllServiceMetadataRef`, `getAllLocalServiceMetadata`
- Run SwiftLint and SwiftFormat; fix any violations
