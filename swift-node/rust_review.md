Do a line by line detailed analisys of SeiftNoden implementation swift-node/Sources agains RUST node implementation runar-rust/runar-node/src/node.rs

1) request flow .. from the Switt node request.. all the way to local reqeust data flow. and remote request dataflow. Check every step, every details, rules.. line by line.. no assumptions no guesses .. do not skip anything
2) Check the remote service implemetnation - init, start, actions impl, event handling, integration with the network components. 
3) service registry (including services , actions , events, everything.. . compare everyrthing... do not skip anyhting.. 
4) Tue use of Anyvalue and serialization (ArcValue in rust) in all these components  be methodical and systematic

Prodiuce a full detailed report that we can use to fix all issues an gaps in the Swift IMPL - THe only accceptable differences (which u dont need to add to your report) are langauge differences.

API and Fielod names must match, bust rust use name_sub_name format and seift uses nameSubName format. that is fine. but the name but still match. Argument order must match.. everything.

LANGUAGE DIFFERENCES (ACCEPTABLE):
Rust: Arc::new(NodeKeyManagerWrapper(...)) vs Swift: keysManager directly ✅
Rust: HashMap::new() vs Swift: [:] dictionary literal ✅
Rust: ArcValue::new_primitive() vs Swift: AnyValue.primitive() ✅
Rust: response.serialize(Some(&context)) vs Swift: response.serialize(context: context) ✅