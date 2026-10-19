// Monotonic time for cache TTLs (P03-00F F3). The device wall clock can be set back by the user;
// CLOCK_MONOTONIC_RAW cannot. A failing source makes the cache fail closed (purge + typed error).
import Foundation
import XRAIVaultContracts

public protocol UptimeSource: Sendable {
    /// Seconds of monotonic uptime. Must never decrease within a process. Throws when unavailable.
    func uptimeSeconds() throws -> Int64
}

/// `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)`: unaffected by wall-clock changes; pauses in deep
/// sleep on some platforms, which only makes a TTL LONGER in uptime terms while the device was asleep
/// — the app layer purges on lock/background to cover that window.
public struct SystemUptime: UptimeSource {
    public init() {}
    public func uptimeSeconds() throws -> Int64 {
        let ns = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        guard ns > 0 else { throw VaultError.clockUnavailable }
        return Int64(ns / 1_000_000_000)
    }
}

/// Process-wide serialization of key-set mutations per (service, keyID) (P03-00F F4).
/// `readPointer → SecItemAdd → SecItemUpdate` is NOT an atomic compare-and-set in the Keychain;
/// within ONE process every `KeychainKeyProvider` instance for the same key set takes this lock
/// around rotation/retire/forget/repair/wipe, so instances cannot interleave. Across processes
/// (app vs. extension) there is no lock: multi-writer rotation is BLOCKED — only the main app may
/// rotate (ownership rule, see ADR-BOOT-007 Amendment F).
enum KeySetSerializer {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var locks: [String: NSLock] = [:]

    static func lock(for service: String, keyID: String) -> NSLock {
        let key = service + "\u{0}" + keyID
        registryLock.lock(); defer { registryLock.unlock() }
        if let l = locks[key] { return l }
        let l = NSLock()
        locks[key] = l
        return l
    }
}
