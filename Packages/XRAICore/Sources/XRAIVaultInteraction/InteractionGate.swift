// XRAIVaultInteraction — P03-05A GATE 3. Binds a REAL user action to an operation token.
//
// HONEST LIMIT (P03_03_CONSENT_AUTHORITY_SPEC §2.5, reconciled in P03-05A): this is an in-process
// misuse-prevention mechanism. It is NOT an operating-system security boundary and NOT cryptographic
// proof of human intent. Code running in the same process can forge a proof. Its value: every token
// in production traces to one explicit control action inside an active scene, within 5 seconds, used
// once, with the exact scope and purpose the user saw — and nothing else in the app can mint tokens.
import Foundation
import XRAIVaultContracts
import XRAIVaultCryptoKit

/// Why the gate refused.
public enum InteractionFailure: String, Hashable, Sendable {
    case sceneInactive = "SCENE_INACTIVE"
    case proofExpired = "PROOF_EXPIRED"
    case proofConsumed = "PROOF_CONSUMED"
    case proofUnknown = "PROOF_UNKNOWN"
    case kindNotAllowed = "PROOF_KIND_NOT_ALLOWED"
    case purposeMismatch = "PROOF_PURPOSE_MISMATCH"
    case notFromAction = "PROOF_NOT_FROM_CONTROL_ACTION"
}

public struct InteractionError: Error, Hashable, Sendable {
    public let failure: InteractionFailure
    public init(_ f: InteractionFailure) { failure = f }
}

/// What the user physically did. Text-field edits and background transitions are not kinds: they can never mint a proof.
public enum InteractionKind: String, Hashable, Sendable, CaseIterable {
    /// A tap on an explicit control ("Hesapla", "Dışa aktar").
    case tap = "TAP"
    /// A confirmation dialog answered affirmatively ("İzin veriyorum", "Sil").
    case confirmDialog = "CONFIRM_DIALOG"
}

/// Port: whether the scene is active RIGHT NOW (the app layer reads `scenePhase`).
public protocol SceneActivity: Sendable {
    var isActive: Bool { get }
}

/// Opaque proof of ONE user action. Only `InteractionGate.mint` creates it (no public initializer);
/// a value carries no authority by itself — the gate re-checks its own registry.
public struct InteractionProof: Hashable, Sendable {
    public let id: String
    public let kind: InteractionKind
    public let purpose: String
    public let mintedAtUnixSeconds: Int64
    fileprivate init(id: String, kind: InteractionKind, purpose: String, mintedAtUnixSeconds: Int64) {
        self.id = id; self.kind = kind; self.purpose = purpose; self.mintedAtUnixSeconds = mintedAtUnixSeconds
    }
}

/// Which kind of action an operation needs (least privilege, spec §2.1).
public enum InteractionPolicy {
    public static let maxProofAgeSeconds: Int64 = 5

    public static func requiredKind(for scope: OperationScope) -> InteractionKind {
        switch scope {
        case .read, .write, .maintenance: return .tap
        case .exportBackup, .restoreBackup, .releaseQuarantine, .delete, .revokeConsent, .restoreSuspended, .retireKey, .admitRestored, .activateRestored, .reimport, .grantConsent: return .confirmDialog
        }
    }

    /// Purpose the user must have acted FOR (consent-bearing scopes carry it in the scope itself).
    public static func boundPurpose(of scope: OperationScope) -> String? {
        switch scope {
        case .grantConsent(let p), .revokeConsent(let p): return p
        default: return nil
        }
    }
}

/// The only token source for production code. Owns the issuer PRIVATELY: nothing outside this type
/// can call `issue`. Proofs are minted only while the scene is active, live 5 s, are single-use and
/// are bound to the exact scope kind and purpose.
public final class InteractionGate: @unchecked Sendable {
    private let issuer: AuthorizationIssuer
    private let clock: any VaultClock
    private let scene: any SceneActivity
    private let lock = NSLock()
    private var live: [String: InteractionProof] = [:]
    private var consumedProofs: Set<String> = []
    /// Payload-free trail: (proof id, kind, scope description, outcome) — ids and reasons only.
    public private(set) var trail: [InteractionTrailEntry] = []

    /// `issuer` is handed over and must not be retained by the caller (the composition root creates
    /// it inline; a source-scan test forbids `issuer.issue(` and `AuthorizationIssuer(` in app code).
    public init(issuer: AuthorizationIssuer, clock: any VaultClock, scene: any SceneActivity) {
        self.issuer = issuer; self.clock = clock; self.scene = scene
    }

    /// The validator the vault/store consumes tokens through (never the issuer itself).
    public var validator: any AuthorizationValidator { issuer }

    /// Mint a proof for an action the user just performed. Only an ACTIVE scene can mint. The app layer
    /// calls this from inside the control's action closure — never from `onChange`, text edits or
    /// scene-phase transitions.
    public func mint(_ kind: InteractionKind, purpose: String = "") throws -> InteractionProof {
        guard scene.isActive else { record("mint", nil, "\(kind)", .sceneInactive); throw InteractionError(.sceneInactive) }
        let now = try clock.now()
        let proof = InteractionProof(id: RecordID().hex, kind: kind, purpose: purpose, mintedAtUnixSeconds: now)
        lock.lock(); live[proof.id] = proof; lock.unlock()
        record("mint", proof.id, "\(kind)", nil)
        return proof
    }

    /// Turns ONE proof into ONE token for EXACTLY this scope. Refuses: unknown/consumed/expired proofs,
    /// inactive scene, wrong kind for the scope, wrong purpose. Consumes the proof even when the scope
    /// is refused (no second try with the same tap).
    public func authorize(scope: OperationScope, purpose: String = "", proof: InteractionProof, ttlSeconds: Int64 = 60) throws -> OperationAuthorization {
        guard scene.isActive else { record("authorize", proof.id, "\(scope)", .sceneInactive); throw InteractionError(.sceneInactive) }
        let now = try clock.now()
        lock.lock()
        guard !consumedProofs.contains(proof.id) else { lock.unlock(); record("authorize", proof.id, "\(scope)", .proofConsumed); throw InteractionError(.proofConsumed) }
        guard let known = live[proof.id], known == proof else { lock.unlock(); record("authorize", proof.id, "\(scope)", .proofUnknown); throw InteractionError(.proofUnknown) }
        live[proof.id] = nil
        consumedProofs.insert(proof.id)
        lock.unlock()
        guard now - known.mintedAtUnixSeconds <= InteractionPolicy.maxProofAgeSeconds, now >= known.mintedAtUnixSeconds else { record("authorize", proof.id, "\(scope)", .proofExpired); throw InteractionError(.proofExpired) }
        guard known.kind == InteractionPolicy.requiredKind(for: scope) else { record("authorize", proof.id, "\(scope)", .kindNotAllowed); throw InteractionError(.kindNotAllowed) }
        let effectivePurpose = InteractionPolicy.boundPurpose(of: scope) ?? purpose
        guard known.purpose == effectivePurpose else { record("authorize", proof.id, "\(scope)", .purposeMismatch); throw InteractionError(.purposeMismatch) }
        let token = try issuer.issue(scope: scope, purpose: effectivePurpose, ttlSeconds: ttlSeconds)
        record("authorize", proof.id, "\(scope)", nil)
        return token
    }

    /// Drops proofs older than the window (housekeeping; expiry is enforced at `authorize` regardless).
    public func purge() throws {
        let now = try clock.now()
        lock.lock(); live = live.filter { now - $0.value.mintedAtUnixSeconds <= InteractionPolicy.maxProofAgeSeconds }; lock.unlock()
    }

    private func record(_ action: String, _ proofID: String?, _ scope: String, _ failure: InteractionFailure?) {
        lock.lock(); trail.append(InteractionTrailEntry(action: action, proofID: proofID, scope: scope, failure: failure)); if trail.count > 1_000 { trail.removeFirst(trail.count - 1_000) }; lock.unlock()
    }
}

/// Payload-free trail entry (ids, kinds, scopes, reason codes — never values).
public struct InteractionTrailEntry: Hashable, Sendable {
    public let action: String
    public let proofID: String?
    public let scope: String
    public let failure: InteractionFailure?
}
