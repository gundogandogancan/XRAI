// Trusted time and operation-token issuer for the application layer (H2 G3).
// HONESTY: these run in the same process as the caller. They make misuse explicit and auditable;
// they are not an OS-level security boundary.
import Foundation
import XRAIVaultContracts

/// Wall-clock time from the OS. The device clock can be set back by the user or by the carrier;
/// there is no trusted time source on-device. Pair with `MonotonicGuardClock`.
public struct SystemClock: VaultClock {
    public init() {}
    public func now() throws -> Int64 { Int64(Date().timeIntervalSince1970.rounded(.down)) }
}

/// Effective-time policy (P02-02 GATE 0A): the returned time NEVER goes below the highest value
/// observed in this process. A base clock within `toleranceSeconds` below the high-water mark
/// yields the high-water mark itself (so a revoked consent or an expired token cannot come back);
/// a base clock further back throws `clockRegressed`. Limits: a clock set back BEFORE the first
/// observation is undetectable; the high-water mark is per process (persisting it is AUTHZ_PERSISTENCE).
public final class MonotonicGuardClock: VaultClock, @unchecked Sendable {
    public let toleranceSeconds: Int64
    private let base: any VaultClock
    private let lock = NSLock()
    private var highWater: Int64?

    public init(wrapping base: any VaultClock, toleranceSeconds: Int64 = 300) {
        self.base = base
        self.toleranceSeconds = toleranceSeconds
    }

    public func now() throws -> Int64 {
        let t = try base.now()
        lock.lock(); defer { lock.unlock() }
        if let hw = highWater {
            if t < hw - toleranceSeconds { throw VaultError.clockRegressed }
            if t < hw { return hw }   // never hand out time below the mark
        }
        highWater = t
        return t
    }
}

/// Issues short-lived, single-use, scoped tokens and validates them atomically. Tokens constructed
/// anywhere else have unknown ids and are rejected. Owned by the application composition root.
public final class AuthorizationIssuer: AuthorizationValidator, @unchecked Sendable {
    private let clock: any VaultClock
    private let lock = NSLock()
    private var issued: [String: OperationAuthorization] = [:]
    private var consumed: Set<String> = []

    public init(clock: any VaultClock) { self.clock = clock }

    /// Issues a token. Called by the application layer in direct response to a user action or a
    /// scheduled maintenance job. `ttlSeconds` is capped at `OperationAuthorization.maxTTLSeconds`.
    public func issue(scope: OperationScope, purpose: String = "", ttlSeconds: Int64 = 60) throws -> OperationAuthorization {
        guard ttlSeconds > 0, ttlSeconds <= OperationAuthorization.maxTTLSeconds else { throw VaultError.authorizationInvalid(.ttlTooLong) }
        let now = try clock.now()
        let token = OperationAuthorization(id: RecordID().hex, scope: scope, purpose: purpose, issuedAtUnixSeconds: now, expiresAtUnixSeconds: now + ttlSeconds)
        lock.lock(); issued[token.id] = token; lock.unlock()
        return token
    }

    public func consume(tokenID: String, atUnixSeconds now: Int64) throws -> OperationAuthorization {
        lock.lock(); defer { lock.unlock() }
        // Replay is reported as such (ids of consumed tokens are retained; they are 128-bit random
        // and small, so the set grows by one entry per operation until the process ends).
        guard !consumed.contains(tokenID) else { throw VaultError.authorizationInvalid(.alreadyConsumed) }
        guard let t = issued[tokenID] else { throw VaultError.authorizationInvalid(.unknownToken) }
        guard now >= t.issuedAtUnixSeconds else { throw VaultError.authorizationInvalid(.notYetValid) }
        guard now < t.expiresAtUnixSeconds else { throw VaultError.authorizationInvalid(.expired) }
        consumed.insert(tokenID)
        issued[tokenID] = nil
        return t
    }

    /// Drops expired, never-consumed tokens.
    public func purge() throws {
        let now = try clock.now()
        lock.lock(); defer { lock.unlock() }
        issued = issued.filter { $0.value.expiresAtUnixSeconds > now }
    }
}
