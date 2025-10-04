GOAL #1 IMplement removeRemoteActionHandler properly

/// Remove a remote action handler
    public func removeRemoteActionHandler(topicPath: TopicPath) async throws {
        logger.debug("Removing remote action handler for: \(topicPath.asString())")

        //TODO: 
        // Remove from remote action handlers trie
        // Note: PathTrie doesn't have a simple remove method, so we'll leave this as TODO
        logger.trace("removeRemoteActionHandler: Not fully implemented - PathTrie remove method needed")

        logger.trace("Removed remote action handler for: \(topicPath.asString())")
    }

as the comment sayhs it depends on PathTrie also beign properly implemented and provigind a remove method
Fix PathTrie and implement the remove_values method like in the RUST version: runar-common/src/routing/path_registry.rs line 96

GOAL #2 IMplement getAllSubscriptions properly swift-node/Sources/SwiftNode/ServiceRegistry.swift

The TODO says: // TODO: Implement proper getAllSubscriptions when PathTrie provides access to all networks

RUST reference:
pub async fn get_all_subscriptions(
        &self,
        include_internal_services: bool,
    ) -> Result<Vec<SubscriptionMetadata>> {
        let subscriptions = self.event_subscriptions.read().await;
        let all_values = subscriptions.get_all_values();

        let mut result = Vec::new();

        for subscription_vec in all_values {
            for (_, _, metadata) in subscription_vec {
                // Filter out internal services if not included
                if !include_internal_services {
                    // metadata.path is a full topic path including network id prefix
                    let tp = TopicPath::from_full_path(&metadata.path).map_err(|e| {
                        anyhow!("Invalid subscription topic path {}: {e}", metadata.path)
                    })?;
                    let service_path = tp.service_path();
                    if is_internal_service(service_path.as_str()) {
                        continue;
                    }
                }
                result.push(metadata);
            }
        }

        Ok(result)
    }

FIX Seift PathTrie to have the method get_all_values - rust reference:
pub fn get_all_values(&self) -> Vec<T> {
    let mut results = Vec::new();
    for network_trie in self.networks.values() {
        network_trie.collect_all_values_internal(&mut results);
    }
    results
}

GOAL 3: Make Sefit pathTrie 100% aligned to the RUST version.. nothing more nothing less. it must have all the same method and behave excatly the same way
/Users/rafael/dev/runar-rust/runar-common/src/routing/path_registry.rs


Goal 4: RE implement RemoteService createFromCapabilities to follow EXACTLY the same rules as teh RUST implementation. 
pub async fn create_from_capabilities(
        config: CreateRemoteServicesConfig,
        dependencies: RemoteServiceDependencies,
    ) -> Result<Vec<Arc<RemoteService>>> {
        log_info!(
            dependencies.logger,
            "Creating RemoteServices from {} service metadata entries",
            config.services.len()
        );

        // The transport is guaranteed to be available via the dependency injection contract.

        // Create remote services for each service metadata
        let mut remote_services = Vec::new();

        for service_metadata in config.services {
            // Create a topic path using the service path (not the name)
            let service_path = match TopicPath::new(
                &service_metadata.service_path,
                &service_metadata.network_id,
            ) {
                Ok(path) => path,
                Err(e) => {
                    log_error!(
                        dependencies.logger,
                        "Invalid service path '{path}': {e}",
                        path = service_metadata.service_path
                    );
                    continue;
                }
            };

            // Prepare config for RemoteService::new
            let rs_config = RemoteServiceConfig {
                name: service_metadata.name.clone(),
                service_topic: service_path,
                version: service_metadata.version.clone(),
                description: service_metadata.description.clone(),
                peer_node_id: config.peer_node_id.clone(),
                request_timeout_ms: config.request_timeout_ms,
            };

            // Prepare dependencies for RemoteService::new (cloning Arcs)
            let rs_dependencies = RemoteServiceDependencies {
                network_transport: dependencies.network_transport.clone(),
                // no keystore/resolver
                local_node_id: dependencies.local_node_id.clone(),
                logger: dependencies.logger.clone(),
                keystore: dependencies.keystore.clone(),
                label_resolver_config: dependencies.label_resolver_config.clone(),
                label_resolver_cache: dependencies.label_resolver_cache.clone(),
            };

            // Create the remote service
            let service = Arc::new(Self::new(rs_config, rs_dependencies));

            // Add actions to the service
            for action in service_metadata.actions {
                service.add_action(action.name.clone(), action)?;
            }
            // Add subscriptions to the service
            // for subscription in service_metadata.subscriptions {
            //     service.add_subscription(subscription.path.clone(), subscription).await?;
            // }
            // Add service to the result list
            remote_services.push(service);
        }

        let service_count = remote_services.len();
        log_info!(
            dependencies.logger,
            "Created {service_count} RemoteService instances"
        );
        Ok(remote_services)
    }

The remove servivces needs RemoteServiceConfig and RemoteServiceDependencies WITH TEH EXACT same fields.. nothing more nothing less.

The seift impl is wrong.. i has :
let remoteService = RemoteService(
                name: serviceMetadata.name,
                serviceTopic: serviceTopic,
                version: serviceMetadata.version,
                description: serviceMetadata.description,
                networkPublicKey: Data(), // TODO: Should be resolved from keystore
                peerNodeId: peerNodeId,
                actions: actionsDict,
                networkTransport: networkTransport,
                logger: logger,
                keystore: keystore,
                labelResolverConfig: labelResolverConfig,
                labelResolverCache: labelResolverCache,
                requestTimeoutMs: requestTimeoutMs
            )


It is passiong networkPublicKey whic is wrong.. networkPublicKey is resolved based on network id:
Rust reference:
let network_id = service.service_topic.network_id();
let network_public_key = match keystore.get_network_public_key_by_id(&network_id) {
Ok(key) => key,
Err(e) => {
    let error_msg =
        format!("Failed to get network public key for network {network_id}: {e}");
    log_error!(logger, "🔒 [RemoteService] {}", error_msg);
    return Box::pin(async move { Err(anyhow::anyhow!(error_msg)) });
}
};
and network_id comes form the service_topicc(TopicPAth).

EVERYTHING in the RemoveServie must match the rust IMPL.


DO NOT DEPRECATE ANYTHING REMOVE IT>> KEEP CODE CLEAN >> NO BACKWARD COMPAT AT ALL FULL REFACTORY ALWAYS