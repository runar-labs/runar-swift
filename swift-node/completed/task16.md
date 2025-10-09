RUST uses events to wait for peers to be disceoveryed...

node2.start().await?;
    logger.debug("✅ Node 2 started");

    logger.debug("⏳ Waiting for nodes to discover each other via multicast and establish QUIC connections...");
    let peer_future2 = node2.on(
        format!(
            "$registry/peer/{node1_id}/discovered",
            node1_id = node1.node_id()
        ),
        Some(runar_node::services::OnOptions {
            timeout: Duration::from_secs(3),
            include_past: None,
        }),
    );
    let peer_future1 = node1.on(
        format!(
            "$registry/peer/{node2_id}/discovered",
            node2_id = node2.node_id()
        ),
        Some(runar_node::services::OnOptions {
            timeout: Duration::from_secs(3),
            include_past: None,
        }),
    );
    //join both futures and wait for both to complete
    let (peer_result2, peer_result1) = tokio::join!(peer_future2, peer_future1);

    // Check for timeout errors and panic if any occurred
    match peer_result2 {
        Ok(_) => logger.debug("✅ Node2 successfully discovered Node1"),
        Err(e) => panic!("❌ Node2 failed to discover Node1 within timeout: {e}"),
    }

    match peer_result1 {
        Ok(_) => logger.debug("✅ Node1 successfully discovered Node2"),
        Err(e) => panic!("❌ Node1 failed to discover Node2 within timeout: {e}"),
    }


    LETS use the same mechnism in Swift tests.. that wil also make suyre thse events are working properly. 

    update swift-node/Tests/SwiftNodeTests/RemoteNetworkTests.swift to use the same machnism in the remote action test