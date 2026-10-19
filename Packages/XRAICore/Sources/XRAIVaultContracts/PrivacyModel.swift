// XRAIVaultContracts — pure, framework-free privacy and vault contracts (constitution §74, §83, §84;
// SECURITY_DATA_EGRESS_MATRIX_v3.2; P02 binding security decisions of 2026-10-19; hardening V32-02-01H).
// This module imports NOTHING. It cannot encrypt, store or transmit; it only defines the rules.

/// Sensitivity tier of a stored record. Ordered from least to most sensitive.
public enum PrivacyTier: String, Hashable, Sendable, CaseIterable, Comparable {
    /// Signed, non-personal content (ephemeris bundles, lessons). Never contains user data.
    case publicContent = "SIGNED_CONTENT_PUBLIC"
    case devicePrivate = "DEVICE_ONLY_PRIVATE"
    case deviceSensitive = "DEVICE_ONLY_SENSITIVE"
    case deviceHighSensitivity = "DEVICE_ONLY_HIGH_SENSITIVITY"

    private var rank: Int {
        switch self {
        case .publicContent: return 0
        case .devicePrivate: return 1
        case .deviceSensitive: return 2
        case .deviceHighSensitivity: return 3
        }
    }
    public static func < (lhs: PrivacyTier, rhs: PrivacyTier) -> Bool { lhs.rank < rhs.rank }
}

/// Personal data classes, one per field family of the egress matrix.
public enum DataClass: String, Hashable, Sendable, CaseIterable {
    case birthDate = "birth_date"
    case birthPlace = "birth_place"
    case birthTime = "birth_time"
    case parentsNames = "parents_names"
    case siblingOrder = "sibling_order"
    case spiritualPractices = "spiritual_practices"
    case psychometrics = "psychometrics"
    case journal = "journal"
    case goalRoadmap = "goal_roadmap"
    case evidenceFiles = "evidence_files"
    case consentReceipts = "consent_receipts"
    case derivedResult = "derived_result"

    /// MINIMUM tier (floor) for this class. A record of this class may be sealed or imported at this
    /// tier or higher, never lower (fail closed, V32-02-01H §3).
    public var minimumTier: PrivacyTier {
        switch self {
        case .birthDate, .birthPlace, .birthTime: return .deviceSensitive
        case .parentsNames: return .deviceHighSensitivity
        case .siblingOrder: return .devicePrivate
        case .spiritualPractices, .psychometrics, .journal: return .deviceSensitive
        case .goalRoadmap, .evidenceFiles, .derivedResult: return .devicePrivate
        case .consentReceipts: return .devicePrivate
        }
    }

    /// Default tier equals the floor.
    public var defaultTier: PrivacyTier { minimumTier }

    /// Classes that may be stored only after an explicit purpose-bound consent held by the authority.
    public var requiresPurposeConsentToStore: Bool {
        switch self {
        case .parentsNames, .siblingOrder, .spiritualPractices, .psychometrics, .journal: return true
        default: return false
        }
    }

    /// Third-party information (another person's data): minimization and pseudonym support apply.
    public var isThirdPartyInformation: Bool {
        self == .parentsNames || self == .siblingOrder
    }
}

/// Where data may flow. Every destination not listed as permitted is denied.
public enum Destination: String, Hashable, Sendable, CaseIterable {
    case deviceVault = "DEVICE_VAULT"
    case userEncryptedBackup = "USER_ENCRYPTED_BACKUP"
    case perCallConsentedProvider = "PER_CALL_EXPLICIT_CONSENT_PROVIDER"
    case appleStoreKit = "APPLE_STOREKIT"
    /// Raw personal content never goes to crash logs; only redacted diagnostics may (outside the vault).
    case crashLogs = "CRASH_LOGS"
    case analytics = "ANALYTICS"
    case modelTraining = "MODEL_TRAINING"
    case cloudSync = "CLOUD_SYNC"
    case advertising = "ADVERTISING"
}

/// How long a record lives and what invalidates it (constitution §84).
public enum RetentionClass: String, Hashable, Sendable, CaseIterable {
    case untilUserDeletes = "UNTIL_USER_DELETES"
    case untilConsentRevoked = "UNTIL_CONSENT_REVOKED"
    case derivedInvalidatable = "DERIVED_INVALIDATE_ON_SOURCE_CHANGE"
    /// Never persisted and never included in a backup.
    case sessionOnly = "SESSION_ONLY_NEVER_PERSISTED"
}

/// One consented (dataClass, purpose, destination) triple.
public struct ConsentScope: Hashable, Sendable {
    public let dataClass: DataClass
    /// Purpose chosen by the user, e.g. "symbolic_family_lens".
    public let purpose: String
    public let destination: Destination

    public init(dataClass: DataClass, purpose: String, destination: Destination) {
        self.dataClass = dataClass
        self.purpose = purpose
        self.destination = destination
    }
}

/// An explicit, revocable, optionally expiring consent record. Stored by a `ConsentAuthority`;
/// a receipt VALUE presented by a caller carries no authority by itself (V32-02-01H §2).
public struct ConsentReceipt: Hashable, Sendable {
    public let id: String
    public let scopes: [ConsentScope]
    public let grantedAtUnixSeconds: Int64
    public let expiresAtUnixSeconds: Int64?
    public let revokedAtUnixSeconds: Int64?

    public init(id: String, scopes: [ConsentScope], grantedAtUnixSeconds: Int64, expiresAtUnixSeconds: Int64? = nil, revokedAtUnixSeconds: Int64? = nil) {
        self.id = id
        self.scopes = scopes
        self.grantedAtUnixSeconds = grantedAtUnixSeconds
        self.expiresAtUnixSeconds = expiresAtUnixSeconds
        self.revokedAtUnixSeconds = revokedAtUnixSeconds
    }

    public func isActive(atUnixSeconds now: Int64) -> Bool {
        guard now >= grantedAtUnixSeconds else { return false }
        if let e = expiresAtUnixSeconds, now >= e { return false }
        if let r = revokedAtUnixSeconds, now >= r { return false }
        return true
    }

    public func covers(_ dataClass: DataClass, purpose: String, destination: Destination, atUnixSeconds now: Int64) -> Bool {
        guard isActive(atUnixSeconds: now) else { return false }
        return scopes.contains { $0.dataClass == dataClass && $0.purpose == purpose && $0.destination == destination }
    }

    public func revoked(atUnixSeconds t: Int64) -> ConsentReceipt {
        ConsentReceipt(id: id, scopes: scopes, grantedAtUnixSeconds: grantedAtUnixSeconds, expiresAtUnixSeconds: expiresAtUnixSeconds, revokedAtUnixSeconds: t)
    }
}

/// Proof that the authority holds an active grant. Only a `ConsentAuthority` creates these.
public struct ConsentGrant: Hashable, Sendable {
    public let receiptID: String
    public let scope: ConsentScope
    public init(receiptID: String, scope: ConsentScope) { self.receiptID = receiptID; self.scope = scope }
}

/// Port: the trusted consent registry. The vault asks it; it never trusts receipts handed in by callers.
public protocol ConsentAuthority: Sendable {
    func activeGrant(for dataClass: DataClass, purpose: String, destination: Destination, atUnixSeconds now: Int64) -> ConsentGrant?
}

/// Deny-by-default data-flow policy. Pure function of (dataClass, destination, authority state).
public enum VaultPolicy {
    /// Destinations that can never receive raw personal data regardless of consent (decision 6, §83, V32-02-01H §4).
    public static let hardDeniedForPersonalData: Set<Destination> = [.analytics, .modelTraining, .cloudSync, .advertising, .crashLogs]

    /// Destinations permitted without a consent grant (storage itself is gated separately by `mayStore`).
    public static let destinationsWithoutConsent: Set<Destination> = [.deviceVault, .userEncryptedBackup]

    public static func decide(
        _ dataClass: DataClass,
        to destination: Destination,
        purpose: String,
        authority: any ConsentAuthority,
        atUnixSeconds now: Int64
    ) -> PolicyDecision {
        if hardDeniedForPersonalData.contains(destination) { return .denied(reason: .hardRule) }
        if destinationsWithoutConsent.contains(destination) { return .allowed }
        if destination == .perCallConsentedProvider || destination == .appleStoreKit {
            guard authority.activeGrant(for: dataClass, purpose: purpose, destination: destination, atUnixSeconds: now) != nil else {
                return .denied(reason: .consentRequired)
            }
            return .allowed
        }
        return .denied(reason: .notListed)
    }

    /// Storing a record in the vault: consent gate for the sensitive classes, checked against the authority.
    public static func mayStore(_ dataClass: DataClass, purpose: String, authority: any ConsentAuthority, atUnixSeconds now: Int64) -> PolicyDecision {
        guard dataClass.requiresPurposeConsentToStore else { return .allowed }
        guard authority.activeGrant(for: dataClass, purpose: purpose, destination: .deviceVault, atUnixSeconds: now) != nil else {
            return .denied(reason: .consentRequired)
        }
        return .allowed
    }

    /// Including a record in a user-held encrypted backup.
    public static func mayBackup(_ dataClass: DataClass, retention: RetentionClass, userInitiated: Bool) -> PolicyDecision {
        guard userInitiated else { return .denied(reason: .userInitiationRequired) }
        guard retention != .sessionOnly else { return .denied(reason: .sessionOnlyNeverPersisted) }
        return decide(dataClass, to: .userEncryptedBackup, purpose: "", authority: NoConsentAuthority(), atUnixSeconds: 0)
    }

    /// Tier floor check used at seal time and at import time.
    public static func validateTier(_ tier: PrivacyTier, for dataClass: DataClass) throws {
        if tier < dataClass.minimumTier {
            throw VaultError.privacyTierBelowMinimum(dataClass: dataClass, required: dataClass.minimumTier, got: tier)
        }
    }
}

/// Authority that holds no grants. Used where a destination needs no consent so no authority is consulted.
public struct NoConsentAuthority: ConsentAuthority {
    public init() {}
    public func activeGrant(for dataClass: DataClass, purpose: String, destination: Destination, atUnixSeconds now: Int64) -> ConsentGrant? { nil }
}

public enum PolicyDecision: Hashable, Sendable {
    case allowed
    case denied(reason: DenialReason)
    public var isAllowed: Bool { self == .allowed }
}

public enum DenialReason: String, Hashable, Sendable {
    case hardRule = "HARD_RULE_NEVER"
    case consentRequired = "CONSENT_REQUIRED"
    case notListed = "DESTINATION_NOT_LISTED"
    case userInitiationRequired = "USER_INITIATION_REQUIRED"
    case sessionOnlyNeverPersisted = "SESSION_ONLY_NEVER_PERSISTED"
}
