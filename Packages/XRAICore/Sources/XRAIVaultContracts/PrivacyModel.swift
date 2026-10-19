// XRAIVaultContracts — pure, framework-free privacy and vault contracts (constitution §74, §83, §84;
// SECURITY_DATA_EGRESS_MATRIX_v3.2; P02 binding security decisions of 2026-10-19).
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

    /// Default tier from SECURITY_DATA_EGRESS_MATRIX_v3.2 (and decision 6 for family data).
    public var defaultTier: PrivacyTier {
        switch self {
        case .birthDate, .birthPlace, .birthTime: return .deviceSensitive
        case .parentsNames: return .deviceHighSensitivity
        case .siblingOrder: return .devicePrivate
        case .spiritualPractices, .psychometrics, .journal: return .deviceSensitive
        case .goalRoadmap, .evidenceFiles, .derivedResult: return .devicePrivate
        case .consentReceipts: return .devicePrivate
        }
    }

    /// Classes that may be stored only after an explicit purpose-bound consent receipt.
    public var requiresPurposeConsentToStore: Bool {
        switch self {
        case .parentsNames, .siblingOrder, .spiritualPractices, .psychometrics, .journal: return true
        default: return false
        }
    }

    /// Third-party information (another person's data) — minimization and pseudonym support apply.
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
    case sessionOnly = "SESSION_ONLY_NEVER_PERSISTED"
}

/// One consented (dataClass, purpose, destination) triple.
public struct ConsentScope: Hashable, Sendable {
    public let dataClass: DataClass
    /// Free-text purpose chosen by the user, e.g. "symbolic_family_name_lens".
    public let purpose: String
    public let destination: Destination

    public init(dataClass: DataClass, purpose: String, destination: Destination) {
        self.dataClass = dataClass
        self.purpose = purpose
        self.destination = destination
    }
}

/// An explicit, revocable consent record. Time is injected as Unix seconds (no clock in this module).
public struct ConsentReceipt: Hashable, Sendable {
    public let id: String
    public let scopes: [ConsentScope]
    public let grantedAtUnixSeconds: Int64
    public let revokedAtUnixSeconds: Int64?

    public init(id: String, scopes: [ConsentScope], grantedAtUnixSeconds: Int64, revokedAtUnixSeconds: Int64? = nil) {
        self.id = id
        self.scopes = scopes
        self.grantedAtUnixSeconds = grantedAtUnixSeconds
        self.revokedAtUnixSeconds = revokedAtUnixSeconds
    }

    public func isActive(atUnixSeconds now: Int64) -> Bool {
        guard now >= grantedAtUnixSeconds else { return false }
        if let r = revokedAtUnixSeconds, now >= r { return false }
        return true
    }

    public func covers(_ dataClass: DataClass, purpose: String, destination: Destination, atUnixSeconds now: Int64) -> Bool {
        guard isActive(atUnixSeconds: now) else { return false }
        return scopes.contains { $0.dataClass == dataClass && $0.purpose == purpose && $0.destination == destination }
    }

    /// Returns a revoked copy. Revocation is append-only in spirit: the original receipt is kept.
    public func revoked(atUnixSeconds t: Int64) -> ConsentReceipt {
        ConsentReceipt(id: id, scopes: scopes, grantedAtUnixSeconds: grantedAtUnixSeconds, revokedAtUnixSeconds: t)
    }
}

/// Deny-by-default data-flow policy. Pure function of (dataClass, destination, consent).
public enum VaultPolicy {
    /// Destinations that can never receive personal data regardless of consent (decision 6, §83).
    public static let hardDeniedForPersonalData: Set<Destination> = [.analytics, .modelTraining, .cloudSync, .advertising]

    /// Destinations permitted without any consent receipt.
    public static func destinationsWithoutConsent(for dataClass: DataClass) -> Set<Destination> {
        // Everything personal stays in the device vault; a user-initiated encrypted backup is the only
        // other default destination. Nothing else, not even crash logs.
        _ = dataClass
        return [.deviceVault, .userEncryptedBackup]
    }

    public static func decide(
        _ dataClass: DataClass,
        to destination: Destination,
        consent: ConsentReceipt?,
        purpose: String,
        atUnixSeconds now: Int64
    ) -> PolicyDecision {
        if hardDeniedForPersonalData.contains(destination) {
            return .denied(reason: .hardRule)
        }
        if destinationsWithoutConsent(for: dataClass).contains(destination) {
            return .allowed
        }
        if destination == .perCallConsentedProvider || destination == .crashLogs || destination == .appleStoreKit {
            guard let c = consent, c.covers(dataClass, purpose: purpose, destination: destination, atUnixSeconds: now) else {
                return .denied(reason: .consentRequired)
            }
            return .allowed
        }
        return .denied(reason: .notListed)
    }

    /// Storing a record in the vault: consent gate for the sensitive classes.
    public static func mayStore(_ dataClass: DataClass, consent: ConsentReceipt?, purpose: String, atUnixSeconds now: Int64) -> PolicyDecision {
        guard dataClass.requiresPurposeConsentToStore else { return .allowed }
        guard let c = consent, c.covers(dataClass, purpose: purpose, destination: .deviceVault, atUnixSeconds: now) else {
            return .denied(reason: .consentRequired)
        }
        return .allowed
    }
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
}
