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

    /// `initialHighWaterSeconds` (P03-04 H3): the mark persisted by the store from an earlier
    /// launch, so a wall clock set back across relaunches still cannot hand out earlier time.
    public init(wrapping base: any VaultClock, toleranceSeconds: Int64 = 300, initialHighWaterSeconds: Int64? = nil) {
        self.base = base
        self.toleranceSeconds = toleranceSeconds
        self.highWater = initialHighWaterSeconds
    }

    /// The highest effective time handed out so far (persisted by the store on every mutation).
    public var highWaterMark: Int64? { lock.lock(); defer { lock.unlock() }; return highWater }

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
    private var counter: UInt64 = 0
    /// P03-04 H3: process epoch. The store persists it and increments it on every open and every
    /// restore; a token id carries its epoch, so a token from an earlier epoch is rejected outright
    /// (`epochMismatch`) instead of relying on a bounded ring of consumed ids. Epoch 0 = no store.
    public let epoch: UInt64

    public init(clock: any VaultClock, epoch: UInt64 = 0) { self.clock = clock; self.epoch = epoch }

    /// Issues a token. Called by the application layer in direct response to a user action or a
    /// scheduled maintenance job. `ttlSeconds` is capped at `OperationAuthorization.maxTTLSeconds`.
    /// Token id = epoch ‖ counter ‖ 128-bit random (all hex, colon separated).
    public func issue(scope: OperationScope, purpose: String = "", ttlSeconds: Int64 = 60) throws -> OperationAuthorization {
        guard ttlSeconds > 0, ttlSeconds <= OperationAuthorization.maxTTLSeconds else { throw VaultError.authorizationInvalid(.ttlTooLong) }
        let now = try clock.now()
        lock.lock(); defer { lock.unlock() }
        counter &+= 1
        let id = String(epoch, radix: 16) + ":" + String(counter, radix: 16) + ":" + RecordID().hex
        let token = OperationAuthorization(id: id, scope: scope, purpose: purpose, issuedAtUnixSeconds: now, expiresAtUnixSeconds: now + ttlSeconds)
        issued[token.id] = token
        return token
    }

    /// Epoch encoded in a token id, if well-formed.
    public static func epoch(ofTokenID id: String) -> UInt64? {
        guard let colon = id.firstIndex(of: ":") else { return nil }
        return UInt64(id[id.startIndex..<colon], radix: 16)
    }

    public func consume(tokenID: String, atUnixSeconds now: Int64) throws -> OperationAuthorization {
        lock.lock(); defer { lock.unlock() }
        guard let tokenEpoch = AuthorizationIssuer.epoch(ofTokenID: tokenID) else { throw VaultError.authorizationInvalid(.unknownToken) }
        guard tokenEpoch == epoch else { throw VaultError.authorizationInvalid(.epochMismatch) }
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

    /// P03-05A PRE-01: the same checks as `consume`, without consuming.
    public func validate(tokenID: String, atUnixSeconds now: Int64) throws -> OperationAuthorization {
        lock.lock(); defer { lock.unlock() }
        guard let tokenEpoch = AuthorizationIssuer.epoch(ofTokenID: tokenID) else { throw VaultError.authorizationInvalid(.unknownToken) }
        guard tokenEpoch == epoch else { throw VaultError.authorizationInvalid(.epochMismatch) }
        guard !consumed.contains(tokenID) else { throw VaultError.authorizationInvalid(.alreadyConsumed) }
        guard let t = issued[tokenID] else { throw VaultError.authorizationInvalid(.unknownToken) }
        guard now >= t.issuedAtUnixSeconds else { throw VaultError.authorizationInvalid(.notYetValid) }
        guard now < t.expiresAtUnixSeconds else { throw VaultError.authorizationInvalid(.expired) }
        return t
    }

    /// Drops expired, never-consumed tokens.
    public func purge() throws {
        let now = try clock.now()
        lock.lock(); defer { lock.unlock() }
        issued = issued.filter { $0.value.expiresAtUnixSeconds > now }
    }
}
