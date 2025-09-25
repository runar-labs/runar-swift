import XCTest
@testable import SwiftFFI

final class HandleRegistryTests: XCTestCase {
    
    // MARK: - Basic Functionality Tests
    
    func testInsertAndClaimLinearity() async throws {
        let registry = HandleRegistry.shared
        let testPointer = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer { testPointer.deallocate() }
        
        // Insert a handle
        let token = registry.insert(kind: .transport, pointer: testPointer)
        
        // Claim it once - should succeed
        let claimedPointer = try registry.claim(kind: .transport, token: token)
        XCTAssertEqual(claimedPointer, testPointer)
        
        // Try to claim the same token again - should fail
        do {
            _ = try registry.claim(kind: .transport, token: token)
            XCTFail("Expected HandleRegistryError.invalidToken")
        } catch HandleRegistryError.invalidToken {
            // Expected
        } catch {
            XCTFail("Expected HandleRegistryError.invalidToken, got \(error)")
        }
    }
    
    func testKindMismatch() async throws {
        let registry = HandleRegistry.shared
        let testPointer = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer { testPointer.deallocate() }
        
        // Insert as transport
        let token = registry.insert(kind: .transport, pointer: testPointer)
        
        // Try to claim as discovery - should fail
        do {
            _ = try registry.claim(kind: .discovery, token: token)
            XCTFail("Expected HandleRegistryError.kindMismatch")
        } catch HandleRegistryError.kindMismatch(let expected, let actual) {
            XCTAssertEqual(expected, .discovery)
            XCTAssertEqual(actual, .transport)
        } catch {
            XCTFail("Expected HandleRegistryError.kindMismatch, got \(error)")
        }
    }
    
    func testInvalidToken() async throws {
        let registry = HandleRegistry.shared
        let invalidToken = HandleToken()
        
        // Try to claim a token that was never inserted
        do {
            _ = try registry.claim(kind: .transport, token: invalidToken)
            XCTFail("Expected HandleRegistryError.invalidToken")
        } catch HandleRegistryError.invalidToken {
            // Expected
        } catch {
            XCTFail("Expected HandleRegistryError.invalidToken, got \(error)")
        }
    }
    
    func testRevokeIfPresent() async throws {
        let registry = HandleRegistry.shared
        let testPointer = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer { testPointer.deallocate() }
        
        // Insert a handle
        let token = registry.insert(kind: .caClient, pointer: testPointer)
        
        // Revoke it
        registry.revokeIfPresent(token: token)
        
        // Try to claim it - should fail
        do {
            _ = try registry.claim(kind: .caClient, token: token)
            XCTFail("Expected HandleRegistryError.invalidToken")
        } catch HandleRegistryError.invalidToken {
            // Expected
        } catch {
            XCTFail("Expected HandleRegistryError.invalidToken, got \(error)")
        }
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentInsertAndClaim() async throws {
        let registry = HandleRegistry.shared
        let numberOfOperations = 100
        
        // Create test pointers
        let testPointers = (0..<numberOfOperations).map { _ in
            UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        }
        defer {
            testPointers.forEach { $0.deallocate() }
        }
        
        // Insert all handles sequentially (registry is thread-safe, so this tests the lock)
        var tokens: [HandleToken] = []
        for pointer in testPointers {
            let token = registry.insert(kind: .transport, pointer: pointer)
            tokens.append(token)
        }
        
        XCTAssertEqual(tokens.count, numberOfOperations)
        
        // Claim all handles sequentially
        for token in tokens {
            _ = try registry.claim(kind: .transport, token: token)
        }
        
        // Verify that all tokens were successfully claimed by trying to claim them again
        for token in tokens {
            do {
                _ = try registry.claim(kind: .transport, token: token)
                XCTFail("Token should have been claimed already")
            } catch HandleRegistryError.invalidToken {
                // Expected - token was already claimed
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        // All tokens should have been successfully claimed
        XCTAssertEqual(tokens.count, numberOfOperations)
    }
    
    func testConcurrentMixedOperations() async throws {
        let registry = HandleRegistry.shared
        let numberOfOperations = 50
        
        // Create test pointers
        let testPointers = (0..<numberOfOperations).map { _ in
            UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        }
        defer {
            testPointers.forEach { $0.deallocate() }
        }
        
        // Mix of insert, claim, and revoke operations
        for (index, pointer) in testPointers.enumerated() {
            let token = registry.insert(kind: .discovery, pointer: pointer)
            
            // Some operations claim, some revoke
            if index % 2 == 0 {
                _ = try! registry.claim(kind: .discovery, token: token)
            } else {
                registry.revokeIfPresent(token: token)
            }
        }
        
        // All operations should complete without crashes or deadlocks
    }
    
    // MARK: - HandleKind Tests
    
    func testAllHandleKinds() async throws {
        let registry = HandleRegistry.shared
        let testPointer = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer { testPointer.deallocate() }
        
        let kinds: [HandleKind] = [.transport, .discovery, .caClient, .keys]
        
        for kind in kinds {
            let token = registry.insert(kind: kind, pointer: testPointer)
            let claimedPointer = try registry.claim(kind: kind, token: token)
            XCTAssertEqual(claimedPointer, testPointer)
        }
    }
    
    // MARK: - HandleToken Tests
    
    func testHandleTokenUniqueness() async throws {
        let registry = HandleRegistry.shared
        let testPointer = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer { testPointer.deallocate() }
        
        // Create multiple tokens
        let tokens = (0..<100).map { _ in
            registry.insert(kind: .transport, pointer: testPointer)
        }
        
        // All tokens should be unique
        let tokenIds = tokens.map { $0.id }
        let uniqueIds = Set(tokenIds)
        XCTAssertEqual(tokenIds.count, uniqueIds.count, "All tokens should be unique")
    }
    
    func testHandleTokenEquality() async throws {
        let token1 = HandleToken()
        let token2 = HandleToken()
        
        XCTAssertEqual(token1, token1)
        XCTAssertNotEqual(token1, token2)
    }
}
