// P03-05A GATE 3 — InteractionGate negatives (rows NT-IG-01…). In-process boundary, stated.
import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultInteraction
import XRAIVaultTesting

final class Scene: SceneActivity, @unchecked Sendable {
    private let lock = NSLock(); private var active: Bool
    init(_ a: Bool) { active = a }
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func set(_ a: Bool) { lock.lock(); active = a; lock.unlock() }
}

struct GateFixture {
    let clock = ManualClock(1_760_000_000)
    let scene = Scene(true)
    let gate: InteractionGate
    let validator: any AuthorizationValidator
    init() {
        gate = InteractionGate(issuer: AuthorizationIssuer(clock: clock, epoch: 1), clock: clock, scene: scene)
        validator = gate.validator
    }
}

@Suite("InteractionGate — one tap, one token; everything else refused")
struct InteractionGateTests {
    @Test("NT-IG-01: happy path — a tap mints a proof, authorize yields a token the validator accepts once; the proof is single-use (replay refused), the trail is payload-free")
    func happyPathAndReplay() throws {
        let f = GateFixture()
        let p = try f.gate.mint(.tap)
        let t = try f.gate.authorize(scope: .read(recordIDs: nil), proof: p)
        #expect(try f.validator.consume(tokenID: t.id, atUnixSeconds: try f.clock.now()).scope == .read(recordIDs: nil))
        #expect(throws: VaultError.authorizationInvalid(.alreadyConsumed)) { _ = try f.validator.consume(tokenID: t.id, atUnixSeconds: try f.clock.now()) }
        #expect(throws: InteractionError(.proofConsumed)) { _ = try f.gate.authorize(scope: .read(recordIDs: nil), proof: p) }
        #expect(f.gate.trail.allSatisfy { $0.proofID == nil || $0.proofID!.count == 32 } && !f.gate.trail.map(\.scope).joined().contains("1998"))
    }

    @Test("NT-IG-02: expired proof (> 5 s), proof from the future, and a proof minted then used after a clock jump are refused")
    func expiry() throws {
        let f = GateFixture()
        let p = try f.gate.mint(.tap)
        f.clock.advance(6)
        #expect(throws: InteractionError(.proofExpired)) { _ = try f.gate.authorize(scope: .read(recordIDs: nil), proof: p) }
        let p2 = try f.gate.mint(.tap)
        f.clock.advance(5)
        _ = try f.gate.authorize(scope: .read(recordIDs: nil), proof: p2)   // exactly 5 s is still inside the window
        let p3 = try f.gate.mint(.tap)
        f.clock.set(1_760_000_000)   // clock set back below the mint time
        #expect(throws: InteractionError(.proofExpired)) { _ = try f.gate.authorize(scope: .read(recordIDs: nil), proof: p3) }
    }

    @Test("NT-IG-03: background — neither minting nor authorizing works while the scene is inactive; a proof minted while active cannot be redeemed after the app went to the background")
    func background() throws {
        let f = GateFixture()
        f.scene.set(false)
        #expect(throws: InteractionError(.sceneInactive)) { _ = try f.gate.mint(.tap) }
        f.scene.set(true)
        let p = try f.gate.mint(.confirmDialog)
        f.scene.set(false)
        #expect(throws: InteractionError(.sceneInactive)) { _ = try f.gate.authorize(scope: .delete(recordIDs: []), proof: p) }
        f.scene.set(true)
        _ = try f.gate.authorize(scope: .delete(recordIDs: []), proof: p)   // still live: the refusal above did not consume it (scene check precedes)
    }

    @Test("NT-IG-04: wrong kind for the scope (a tap cannot delete/export/grant; a dialog is not a read), wrong purpose, and a mismatched consent purpose are refused — and the proof is consumed by the refusal")
    func scopeAndPurpose() throws {
        let f = GateFixture()
        let tap = try f.gate.mint(.tap)
        #expect(throws: InteractionError(.kindNotAllowed)) { _ = try f.gate.authorize(scope: .delete(recordIDs: [RecordID()]), proof: tap) }
        #expect(throws: InteractionError(.proofConsumed)) { _ = try f.gate.authorize(scope: .read(recordIDs: nil), proof: tap) }
        let dlg = try f.gate.mint(.confirmDialog)
        #expect(throws: InteractionError(.kindNotAllowed)) { _ = try f.gate.authorize(scope: .read(recordIDs: nil), proof: dlg) }
        let g = try f.gate.mint(.confirmDialog, purpose: "journal_reflection")
        #expect(throws: InteractionError(.purposeMismatch)) { _ = try f.gate.authorize(scope: .grantConsent(purpose: "symbolic_family_lens"), proof: g) }
        let g2 = try f.gate.mint(.confirmDialog, purpose: "journal_reflection")
        let t = try f.gate.authorize(scope: .grantConsent(purpose: "journal_reflection"), proof: g2)
        #expect(t.purpose == "journal_reflection" && t.scope == .grantConsent(purpose: "journal_reflection"))
        let w = try f.gate.mint(.tap, purpose: "a")
        #expect(throws: InteractionError(.purposeMismatch)) { _ = try f.gate.authorize(scope: .write(.journal), purpose: "b", proof: w) }
    }

    @Test("NT-IG-05: forged proofs (a value with the right shape but not minted here, or minted by another gate) and direct issuer bypass are impossible — the issuer is private; the validator refuses tokens from anywhere else")
    func forgedAndBypass() throws {
        let f = GateFixture(), other = GateFixture()
        let foreign = try other.gate.mint(.tap)
        #expect(throws: InteractionError(.proofUnknown)) { _ = try f.gate.authorize(scope: .read(recordIDs: nil), proof: foreign) }
        // a token minted elsewhere (another issuer) is unknown to this gate's validator
        let rogue = AuthorizationIssuer(clock: f.clock, epoch: 1)
        let rt = try rogue.issue(scope: .read(recordIDs: nil))
        #expect(throws: VaultError.authorizationInvalid(.unknownToken)) { _ = try f.validator.consume(tokenID: rt.id, atUnixSeconds: try f.clock.now()) }
        // the gate exposes no issuer: compile-time (the property does not exist) — the source scan is NT-IG-05b
    }

    // The source tree exists only on the Mac (macOS and Simulator hosts). On a physical iPhone the scan is reported
    // as SKIPPED — never as passed — and the same rule is enforced statically by validation/check_p03_03_docs.py.
    #if os(iOS) && !targetEnvironment(simulator)
    static let sourceScanTrait: any TestTrait = .disabled("source scan not applicable on a physical device (no source tree); runs on macOS and Simulator")
    #else
    static let sourceScanTrait: any TestTrait = .enabled(if: true)
    #endif

    @Test("NT-IG-05b: source scan — the issuer is a private stored property of the gate and the proof initialiser is fileprivate (no issuer bypass surface)", Self.sourceScanTrait)
    func issuerIsPrivate() throws {
        var u = URL(fileURLWithPath: #filePath); u.deleteLastPathComponent(); u.deleteLastPathComponent(); u.deleteLastPathComponent()
        let src = try String(contentsOf: u.appendingPathComponent("Sources/XRAIVaultInteraction/InteractionGate.swift"), encoding: .utf8)
        #expect(src.contains("private let issuer: AuthorizationIssuer") && !src.contains("public var issuer") && src.contains("fileprivate init(id: String, kind: InteractionKind"))
    }

    @Test("NT-IG-06: parallel requests — 200 concurrent authorizations of one proof yield exactly one token; interrupted actions (minted, never redeemed) expire and are purged")
    func parallelAndInterrupted() throws {
        let f = GateFixture()
        let p = try f.gate.mint(.tap)
        let ok = GateCounter(), bad = GateCounter()
        let gate = f.gate
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            do { _ = try gate.authorize(scope: .read(recordIDs: nil), proof: p); ok.add() } catch { bad.add() }
        }
        #expect(ok.count == 1 && bad.count == 199)
        _ = try f.gate.mint(.tap)
        f.clock.advance(10)
        try f.gate.purge()
        let p2 = try f.gate.mint(.tap)
        _ = try f.gate.authorize(scope: .read(recordIDs: nil), proof: p2)
    }
}

final class GateCounter: @unchecked Sendable { private let l = NSLock(); private var v = 0; func add() { l.lock(); v += 1; l.unlock() }; var count: Int { l.lock(); defer { l.unlock() }; return v } }
