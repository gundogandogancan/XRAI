// Access contract for every vault operation (hardening V32-02-01H2, G1–G3).
//
// Three independent checks gate personal data:
//   1. OperationAuthorization — a short-lived, single-use, scoped token issued by the application
//      layer's trusted issuer in response to a real user action or an internal maintenance job.
//      The vault trusts only the issuer's own copy of the token (looked up by id), never the
//      caller's value.
//   2. ConsentAuthority — an active, purpose-bound grant for consent-gated data classes.
//   3. VaultClock — time from the application layer, not from the caller.
// HONESTY: none of this is an operating-system security boundary. All of it runs inside one
// process; malicious code in the same process can bypass Swift access control. These controls
// prevent accidental misuse and make every access explicit and auditable.

/// Port: trusted time. Implementations must come from the application layer (system clock with a
/// monotonic guard), never from request parameters.
public protocol VaultClock: Sendable {
    /// Unix seconds. Throws `clockRegressed` when a guard detects the clock moved backwards beyond tolerance.
    func now() throws -> Int64
}

/// Narrow technical operations that never return plaintext to the caller.
public enum MaintenanceKind: String, Hashable, Sendable, CaseIterable {
    case integrityCheck = "INTEGRITY_CHECK"
    case rewrap = "REWRAP"
}

/// What an authorization token permits. Scopes are exact-match except where a record set narrows them.
public enum OperationScope: Hashable, Sendable {
    /// Seal a new record of this class.
    case write(DataClass)
    /// Read plaintext of the given records (nil = any record, still consent- and purpose-gated).
    case read(recordIDs: Set<RecordID>?)
    /// User data-portability right: create an encrypted backup.
    case exportBackup
    /// Restore an encrypted backup onto this device.
    case restoreBackup
    /// Re-enable records quarantined at restore because their consent was no longer active.
    case releaseQuarantine
    /// User deletion right for the given records (the store layer executes it).
    case delete(recordIDs: Set<RecordID>)
    /// Technical maintenance without plaintext access.
    case maintenance(MaintenanceKind)

    /// Whether this scope covers `op` for `recordID` (nil when the operation is not record-bound).
    public func covers(_ op: OperationScope, recordID: RecordID?) -> Bool {
        switch (self, op) {
        case (.write(let a), .write(let b)): return a == b
        case (.read(let allowed), .read):
            guard let allowed else { return true }
            guard let recordID else { return false }
            return allowed.contains(recordID)
        case (.exportBackup, .exportBackup), (.restoreBackup, .restoreBackup), (.releaseQuarantine, .releaseQuarantine): return true
        case (.delete(let a), .delete(let b)): return b.isSubset(of: a)
        case (.maintenance(let a), .maintenance(let b)): return a == b
        default: return false
        }
    }
}

/// A single-use, short-lived operation token. The id is the only thing the vault uses from the
/// caller's copy; scope, purpose and expiry are taken from the issuer's trusted copy.
public struct OperationAuthorization: Hashable, Sendable {
    public static let maxTTLSeconds: Int64 = 300

    public let id: String
    public let scope: OperationScope
    /// Purpose the user acted for; must equal the record's `consentPurpose` for consent-gated reads.
    public let purpose: String
    public let issuedAtUnixSeconds: Int64
    public let expiresAtUnixSeconds: Int64

    public init(id: String, scope: OperationScope, purpose: String, issuedAtUnixSeconds: Int64, expiresAtUnixSeconds: Int64) {
        self.id = id
        self.scope = scope
        self.purpose = purpose
        self.issuedAtUnixSeconds = issuedAtUnixSeconds
        self.expiresAtUnixSeconds = expiresAtUnixSeconds
    }
}

public enum AuthorizationFailure: String, Hashable, Sendable {
    case unknownToken = "UNKNOWN_TOKEN"
    case alreadyConsumed = "ALREADY_CONSUMED"
    case expired = "EXPIRED"
    case notYetValid = "NOT_YET_VALID"
    case scopeMismatch = "SCOPE_MISMATCH"
    case purposeMismatch = "PURPOSE_MISMATCH"
    case ttlTooLong = "TTL_TOO_LONG"
}

/// Port: the trusted issuer/validator of operation tokens. `consume` must be atomic: a token is
/// returned at most once, and only if the issuer created it and it is within its validity window.
public protocol AuthorizationValidator: Sendable {
    func consume(tokenID: String, atUnixSeconds now: Int64) throws -> OperationAuthorization
}

/// A record restored from backup whose consent is no longer active. Not readable until released
/// with a fresh grant and a `releaseQuarantine` authorization.
public struct QuarantinedRecord: Hashable, Sendable {
    public let envelope: RecordEnvelope
    public let reason: DenialReason
    public init(envelope: RecordEnvelope, reason: DenialReason) { self.envelope = envelope; self.reason = reason }
}

/// Result of a restore: active records and quarantined ones, never silently re-enabled.
public struct RestoreResult: Hashable, Sendable {
    public let active: [RecordEnvelope]
    public let quarantined: [QuarantinedRecord]
    public init(active: [RecordEnvelope], quarantined: [QuarantinedRecord]) { self.active = active; self.quarantined = quarantined }
}

/// Authorization for the store layer to delete records. The vault issues it only through the
/// token path; persistence (future) must consume it.
public struct DeletionGrant: Hashable, Sendable {
    public let recordIDs: Set<RecordID>
    public let authorizedAtUnixSeconds: Int64
    public init(recordIDs: Set<RecordID>, authorizedAtUnixSeconds: Int64) { self.recordIDs = recordIDs; self.authorizedAtUnixSeconds = authorizedAtUnixSeconds }
}
