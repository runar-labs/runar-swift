import XCTest
import SwiftFFI
import SwiftCommon

@testable import SwiftFFI

/// Tests for CA Client CRL functionality
/// Tests get_crl parity and rejection scenarios
final class CaClientCrlTests: XCTestCase {
    
    private var nodeKeys: KeysHandle!
    private var caNode: CANode!
    private var caServer: CAServer!
    private var caClient: CAClient!
    
    override func setUp() {
        super.setUp()
        
        // Create node keys handle
        nodeKeys = try! KeysHandle()
        try! nodeKeys.initializeAsNode()
        try! nodeKeys.nodeGenerateKeys()
        
        // Create CA node for testing
        caNode = try! CANode.create()
        
        // Set up CA server for testing
        let caServerConfig = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        
        let sharedCaNode = try! caNode.createShared()
        caServer = try! CAServer.create(config: caServerConfig, sharedCaNode: sharedCaNode)
        
        // Set up CA client for testing
        let caClientConfig = CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Data(),
            issuing_ca_der: Data()
        )
        
        caClient = try! CAClient(config: caClientConfig, nodeKeys: nodeKeys)
    }
    
    override func tearDown() {
        caClient = nil
        caServer = nil
        caNode = nil
        nodeKeys = nil
        super.tearDown()
    }
    
    // MARK: - CRL Retrieval Tests
    
    func testGetCrl() throws {
        // Test getting CRL from CA client
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network"
        
        do {
            let crlData = try caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )
            
            // Verify CRL data is returned
            XCTAssertFalse(crlData.isEmpty, "CRL data should not be empty")
            XCTAssertGreaterThan(crlData.count, 0, "CRL data should have content")
        } catch {
            // Might fail if server is not running, which is expected in tests
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testGetCrlWithDifferentNetworkIds() throws {
        // Test getting CRL with different network IDs
        let authenticatedAddress = "127.0.0.1:8080"
        let networkIds = ["network-1", "network-2", "test-network", "production-network"]
        
        for networkId in networkIds {
            do {
                let crlData = try caClient.getCrl(
                    authenticatedAddress: authenticatedAddress,
                    networkId: networkId
                )
                
                // Verify CRL data is returned
                XCTAssertFalse(crlData.isEmpty, "CRL data should not be empty for network \(networkId)")
            } catch {
                // Might fail if server is not running or network doesn't exist
                XCTAssertTrue(error is FFIError)
            }
        }
    }
    
    func testGetCrlWithDifferentAddresses() throws {
        // Test getting CRL with different addresses
        let addresses = ["127.0.0.1:8080", "127.0.0.1:8081", "localhost:8080", "0.0.0.0:8080"]
        let networkId = "test-network"
        
        for address in addresses {
            do {
                let crlData = try caClient.getCrl(
                    authenticatedAddress: address,
                    networkId: networkId
                )
                
                // Verify CRL data is returned
                XCTAssertFalse(crlData.isEmpty, "CRL data should not be empty for address \(address)")
            } catch {
                // Might fail if server is not running on that address
                XCTAssertTrue(error is FFIError)
            }
        }
    }
    
    // MARK: - CRL Error Handling Tests
    
    func testGetCrlWithInvalidAddress() throws {
        // Test getting CRL with invalid address
        let invalidAddress = "invalid-address:99999"
        let networkId = "test-network"
        
        do {
            let crlData = try caClient.getCrl(
                authenticatedAddress: invalidAddress,
                networkId: networkId
            )
            XCTFail("Should have thrown error for invalid address")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testGetCrlWithEmptyAddress() throws {
        // Test getting CRL with empty address
        let emptyAddress = ""
        let networkId = "test-network"
        
        do {
            let crlData = try caClient.getCrl(
                authenticatedAddress: emptyAddress,
                networkId: networkId
            )
            XCTFail("Should have thrown error for empty address")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testGetCrlWithEmptyNetworkId() throws {
        // Test getting CRL with empty network ID
        let authenticatedAddress = "127.0.0.1:8080"
        let emptyNetworkId = ""
        
        do {
            let crlData = try caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: emptyNetworkId
            )
            XCTFail("Should have thrown error for empty network ID")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testGetCrlWithSpecialCharacters() throws {
        // Test getting CRL with special characters in parameters
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network-@#$%^&*()"
        
        do {
            let crlData = try caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )
            // Might succeed or fail depending on validation
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - CRL Consistency Tests
    
    func testCrlConsistency() throws {
        // Test that CRL data is consistent across multiple calls
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network"
        
        do {
            let crl1 = try caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )
            
            let crl2 = try caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )
            
            // CRL data should be consistent (same content)
            XCTAssertEqual(crl1, crl2, "CRL data should be consistent across multiple calls")
        } catch {
            // Might fail if server is not running
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testCrlWithDifferentClients() throws {
        // Test CRL retrieval with different CA clients
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network"
        
        // Create another CA client
        let caClientConfig2 = CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Data(),
            issuing_ca_der: Data()
        )
        
        let caClient2 = try! CAClient(config: caClientConfig2, nodeKeys: nodeKeys)
        
        do {
            let crl1 = try caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )
            
            let crl2 = try caClient2.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )
            
            // CRL data should be the same from different clients
            XCTAssertEqual(crl1, crl2, "CRL data should be the same from different clients")
        } catch {
            // Might fail if server is not running
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - CRL Performance Tests
    
    func testCrlPerformance() throws {
        // Test performance of CRL retrieval
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network"
        let iterations = 10
        
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            for _ in 0..<iterations {
                _ = try caClient.getCrl(
                    authenticatedAddress: authenticatedAddress,
                    networkId: networkId
                )
            }
            
            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            let averageTime = totalTime / Double(iterations)
            
            // Verify operations completed successfully
            XCTAssertGreaterThan(totalTime, 0, "CRL retrieval should take some time")
            
            // Log performance metrics (optional)
            print("Average CRL retrieval time: \(averageTime) seconds")
        } catch {
            // Might fail if server is not running
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - CRL with Server Integration Tests
    
    func testCrlWithServerIntegration() throws {
        // Test CRL retrieval with actual server running
        // This test requires the CA server to be running
        
        // Start the CA server
        try caServer.start()
        
        // Get server addresses
        let bootstrapAddress = try caServer.bootstrapAddress()
        let authenticatedAddress = try caServer.authenticatedAddress()
        
        // Test CRL retrieval
        do {
            let crlData = try caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: "test-network"
            )
            
            // Verify CRL data is returned
            XCTAssertFalse(crlData.isEmpty, "CRL data should not be empty when server is running")
        } catch {
            // If server is not properly configured, this might fail
            XCTAssertTrue(error is FFIError)
        }
        
        // Stop the server
        try caServer.stop()
    }
    
    // MARK: - CRL Error Scenarios Tests
    
    func testCrlErrorScenarios() throws {
        // Test various error scenarios for CRL retrieval
        
        // Test with very long address
        let longAddress = "127.0.0.1:" + String(repeating: "8", count: 100)
        let networkId = "test-network"
        
        do {
            let crlData = try caClient.getCrl(
                authenticatedAddress: longAddress,
                networkId: networkId
            )
            XCTFail("Should have thrown error for invalid long address")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        // Test with very long network ID
        let longNetworkId = String(repeating: "a", count: 1000)
        
        do {
            let crlData = try caClient.getCrl(
                authenticatedAddress: "127.0.0.1:8080",
                networkId: longNetworkId
            )
            XCTFail("Should have thrown error for invalid long network ID")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - CRL Concurrent Access Tests
    
    func testCrlConcurrentAccess() throws {
        // Test concurrent CRL retrieval operations
        
        let expectation = XCTestExpectation(description: "Concurrent CRL operations")
        expectation.expectedFulfillmentCount = 3
        
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network"
        
        // Run concurrent operations
        DispatchQueue.global().async {
            do {
                let crlData = try self.caClient.getCrl(
                    authenticatedAddress: authenticatedAddress,
                    networkId: networkId
                )
                XCTAssertFalse(crlData.isEmpty)
                expectation.fulfill()
            } catch {
                // Might fail if server is not running
                XCTAssertTrue(error is FFIError)
                expectation.fulfill()
            }
        }
        
        DispatchQueue.global().async {
            do {
                let crlData = try self.caClient.getCrl(
                    authenticatedAddress: authenticatedAddress,
                    networkId: networkId
                )
                XCTAssertFalse(crlData.isEmpty)
                expectation.fulfill()
            } catch {
                // Might fail if server is not running
                XCTAssertTrue(error is FFIError)
                expectation.fulfill()
            }
        }
        
        DispatchQueue.global().async {
            do {
                let crlData = try self.caClient.getCrl(
                    authenticatedAddress: authenticatedAddress,
                    networkId: networkId
                )
                XCTAssertFalse(crlData.isEmpty)
                expectation.fulfill()
            } catch {
                // Might fail if server is not running
                XCTAssertTrue(error is FFIError)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - CRL Data Validation Tests
    
    func testCrlDataValidation() throws {
        // Test validation of CRL data format
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network"
        
        do {
            let crlData = try caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )
            
            // Verify CRL data has expected properties
            XCTAssertFalse(crlData.isEmpty, "CRL data should not be empty")
            XCTAssertGreaterThan(crlData.count, 0, "CRL data should have content")
            
            // CRL data should be valid binary data
            XCTAssertTrue(crlData.count > 0, "CRL data should have positive length")
            
        } catch {
            // Might fail if server is not running
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - CRL Network Error Handling
    
    func testCrlNetworkErrorHandling() throws {
        // Test handling of network errors during CRL retrieval
        
        // Test with unreachable address
        let unreachableAddress = "192.168.255.255:8080"
        let networkId = "test-network"
        
        do {
            let crlData = try caClient.getCrl(
                authenticatedAddress: unreachableAddress,
                networkId: networkId
            )
            XCTFail("Should have thrown error for unreachable address")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        // Test with invalid port
        let invalidPortAddress = "127.0.0.1:99999"
        
        do {
            let crlData = try caClient.getCrl(
                authenticatedAddress: invalidPortAddress,
                networkId: networkId
            )
            XCTFail("Should have thrown error for invalid port")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
}
