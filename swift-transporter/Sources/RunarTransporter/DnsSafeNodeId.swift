import Foundation

public enum DnsSafeNodeId {
    /// Mirror Rust dns_safe_node_id: '-'→'x', '_'→'y', keep [A-Za-z0-9], else 'z'
    public static func convert(_ nodeId: String) -> String {
        var out = String()
        out.reserveCapacity(nodeId.count)
        for ch in nodeId {
            switch ch {
            case "-": out.append("x")
            case "_": out.append("y")
            default:
                if ch.isLetter || ch.isNumber {
                    out.append(ch)
                } else {
                    out.append("z")
                }
            }
        }
        return out
    }
}
