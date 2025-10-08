@RemoteNetworkTests.swift lets add a test here called testNodeHandshake it has the exact same setup as testRemoteActionCall() but after   peers are discovered it will us teh $registry internal service to get a list of all servvices and that should include local serivces + remote services.. and this test will assert taht.. whe that test works properly it will validate that the disdcovery + handshate is working properly.. and can tick that off.. before we exevute the testRemoteACtionCall which needs this to work properly.. begore we can make a remote call.. and before that we3 als0 need t ofix how we wait for pee4rs discovered.. the proper way as in teh rust test is logger.debug("⏳ Waiting for nodes to discover each other via multicast and establish QUIC connections...");
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
  .. curently the testRemoteActionCall() is doing try await Task.sleep(for: .seconds(2)) // Give time for discovery. .. whi9cn is a HACK.. even adminted in the comments // In a real implementation, this would wait for peer discovery events .. our rules says cleanr.. no hacks.. no shortuts. @code-standards.mdc  so implement the proper wait for peer dfiscovere which is using the events  as in the RUST code  ..   here is the example on how to use the internal $registru service to valite all services (local and remote) @RegistryServiceTests.swift testRegistryServiceListServices()  .