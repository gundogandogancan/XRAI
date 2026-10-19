import Foundation
import XRAIVaultContracts

/// Test double for the trusted consent registry. Only receipts registered HERE grant anything;
/// a receipt value held by a caller is meaningless to the vault.
final class InMemoryConsentAuthority: ConsentAuthority, @unchecked Sendable {
    private let lock = NSLock()
    private var receipts: [String: ConsentReceipt] = [:]

    init(_ receipts: [ConsentReceipt] = []) { for r in receipts { self.receipts[r.id] = r } }

    func register(_ r: ConsentReceipt) { lock.lock(); receipts[r.id] = r; lock.unlock() }
    func revoke(id: String, atUnixSeconds t: Int64) {
        lock.lock(); defer { lock.unlock() }
        if let r = receipts[id] { receipts[id] = r.revoked(atUnixSeconds: t) }
    }

    func activeGrant(for dataClass: DataClass, purpose: String, destination: Destination, atUnixSeconds now: Int64) -> ConsentGrant? {
        lock.lock(); defer { lock.unlock() }
        for r in receipts.values where r.covers(dataClass, purpose: purpose, destination: destination, atUnixSeconds: now) {
            if let s = r.scopes.first(where: { $0.dataClass == dataClass && $0.purpose == purpose && $0.destination == destination }) {
                return ConsentGrant(receiptID: r.id, scope: s)
            }
        }
        return nil
    }
}

/// Naive subsequence search used by the leak checks.
func bytesContain(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard !needle.isEmpty, haystack.count >= needle.count else { return false }
    for i in 0...(haystack.count - needle.count) where haystack[i] == needle[0] {
        if Array(haystack[i..<i + needle.count]) == needle { return true }
    }
    return false
}

func flipByte(_ bytes: [UInt8], at i: Int) -> [UInt8] { var b = bytes; b[i] ^= 0x01; return b }
