import Foundation

public enum LocalDesiredRole: Equatable {
    case initiator
    case responder
}

public struct PeerStateLite: Equatable {
    public let connectionId: Int
    public let initiatorPeerId: String
    public let initiatorNonce: UInt64
    public let responderPeerId: String
    public let responderNonce: UInt64
}

public enum ConnectionRoleLite: Equatable {
    case initiator
    case responder
}

public enum DuplicateResolution {
    /// Determine desired local role from Rust rule: if local_id < peer_id then Initiator else Responder
    public static func desiredLocalRole(localId: String, peerId: String) -> LocalDesiredRole {
        return localId < peerId ? .initiator : .responder
    }

    /// Compute the local role from a PeerStateLite perspective
    public static func localRole(for state: PeerStateLite, localId: String) -> ConnectionRoleLite {
        return state.initiatorPeerId == localId ? .initiator : .responder
    }

    /// Compute the local role for a candidate given initiator/responder peer ids
    public static func localRoleForCandidate(localId: String, candidateInitiatorPeerId: String) -> ConnectionRoleLite {
        return candidateInitiatorPeerId == localId ? .initiator : .responder
    }

    /// Decide whether to pick candidate connection over existing, mirroring Rust `replace_or_keep_connection` logic.
    /// - Returns: true if candidate should replace existing; false to keep existing
    public static func shouldPickCandidate(
        localId: String,
        peerId: String,
        existing: PeerStateLite,
        candidateConnectionId: Int,
        candidateInitiatorPeerId: String,
        candidateInitiatorNonce: UInt64,
        candidateResponderPeerId: String,
        candidateResponderNonce: UInt64
    ) -> Bool {
        // Placeholder rule: replace if existing has zero nonces (placeholder)
        if existing.initiatorNonce == 0 && existing.responderNonce == 0 {
            return true
        }

        let desired = desiredLocalRole(localId: localId, peerId: peerId)
        let existingLocalRole = localRole(for: existing, localId: localId)
        let candidateLocalRole = localRoleForCandidate(localId: localId, candidateInitiatorPeerId: candidateInitiatorPeerId)

        let existingMatches = (desired == .initiator && existingLocalRole == .initiator) || (desired == .responder && existingLocalRole == .responder)
        let candidateMatches = (desired == .initiator && candidateLocalRole == .initiator) || (desired == .responder && candidateLocalRole == .responder)

        switch (existingMatches, candidateMatches) {
        case (false, true):
            return true
        case (true, false):
            return false
        case (true, true):
            // Prefer lower stable id to avoid local flapping
            return candidateConnectionId < existing.connectionId
        case (false, false):
            // Prefer existing for stability
            return false
        }
    }
}


