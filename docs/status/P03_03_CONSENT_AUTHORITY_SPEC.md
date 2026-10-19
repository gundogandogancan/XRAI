# P03_03_CONSENT_AUTHORITY_SPEC — production consent authority and user-interaction binding

**Date:** 2026-10-20 · **Baseline:** `713468e` · Builds on `ConsentAuthority`, `ConsentReceipt`, `AuthorizationIssuer`, `OperationAuthorization`, `MonotonicGuardClock` (ADR-BOOT-005 H2, P02-02 GATE 0). Nothing here is implemented yet except the ports and the in-memory doubles.

Türkçe özet: Amaç ve veri sınıfı bazlı, sürümlü, geri çekilebilir izinler; tek kullanımlık ve süreli işlem yetkileri; gerçek kullanıcı dokunuşunun kanıtı için uygulama katmanında üretilen etkileşim kanıtı; kalıcı tüketilmiş-token ve saat işareti; fail-closed; en az yetki; kullanıcıya anlaşılır izin geçmişi; mahremiyeti koruyan olay kaydı. Form alanına yazmak izin değildir; izin yalnız izin ekranındaki açık eylemle verilir.

## 1. Objects

| object | fields | notes |
|---|---|---|
| `ConsentScope` (exists) | dataClass, purpose, destination | purpose is a registry key (`PurposeID`), not free text, in production |
| `PurposeRegistry` (new) | `PurposeID` → human text (tr/en), data classes allowed, destinations allowed, version, retention class | shipped with the app, versioned; a grant references the purpose **version** it was shown for |
| `ConsentReceipt` (exists; extended) | id, scopes[], grantedAt, expiresAt?, revokedAt?, **purposeVersion**, **interactionProofID**, **supersedes?** | immutable; revocation and re-grant create new receipts (versioning by chain) |
| `ConsentEvent` (new) | id, type {granted, revoked, expired, superseded, viewed}, receiptID, at, **no payload** | append-only event log; the user-visible history is rendered from it |
| `OperationAuthorization` (exists) | id, scope, purpose, issuedAt, expiresAt | single-use, TTL ≤ 300 s |
| `InteractionProof` (new) | id, kind {tap, confirmDialog, biometric?}, sceneActive: Bool, issuedAt, consumedBy: tokenID? | produced only by `InteractionGate` in the app layer, inside the SwiftUI action closure of a consent/confirm control |

## 2. Trusted user interaction (the one tap)

Threat: code anywhere in the process calls `issuer.issue(...)` and acts "as the user". Mitigation (in-process, honest about limits):

1. `AuthorizationIssuer.issue` is **removed from the public surface** of the crypto module and replaced by `InteractionGate.issue(scope:purpose:proof:)` in the app layer. The gate requires an `InteractionProof` that is (a) created within the last 5 s, (b) created while `scenePhase == .active`, (c) unconsumed, (d) of a kind allowed for the scope (`.exportBackup`, `.restoreBackup`, `.delete`, `.releaseQuarantine`, consent grants → `confirmDialog`; `.read`/`.write` → `tap`).
2. `InteractionProof` is minted by a single SwiftUI view modifier (`.consentAction { proof in … }`) that wraps the control's action; the modifier is the only place that can construct a proof (private initializer, same file). Code review + a source-scan test enforce that no other file constructs it.
3. Typing into a text field never mints a proof. Only the explicit control ("Hesapla", "İzin veriyorum", "Dışa aktar") does. Today's `computePreview()` is already the only path that sets a date; the gate formalises it.
4. Proofs and tokens are logged as **events without payload** (ids + kind + timestamps).
5. **Limit stated:** this is not an OS boundary. Malicious code in-process can forge a proof. Real guarantees come from code signing, the App Sandbox, Secure Enclave key usage and, for high-value operations, optional biometric confirmation (`LAContext` + SE `.biometryCurrentSet` key, deferred to a later phase with a UX decision).

## 3. Grant flow

```
user opens consent screen for PurposeID P (version v)
→ screen shows: data classes, destinations, retention, what is derived, how to revoke
→ user taps "İzin veriyorum" → InteractionProof(confirmDialog)
→ InteractionGate issues OperationAuthorization(scope: .grantConsent(P))   [new scope]
→ ConsentAuthority.grant(receipt, authorization) validates token + proof, writes ConsentReceipt (envelope, class consent_receipts) + ConsentEvent(granted)
→ fail-closed: any step missing → no grant, event(denied) with reason code only
```
Revoke is symmetric with scope `.revokeConsent(receiptID)`; effect is immediate for reads (already enforced by `mayRead`), derived data invalidated, the record enters the grace timeline (lifecycle matrix §3).

## 4. Validation rules (all fail-closed)

| rule | where | status |
|---|---|---|
| unknown token id → reject | `AuthorizationIssuer.consume` | EXISTS, tested |
| consumed token → reject (replay) | same | EXISTS, tested; **consumed set persisted** in P03-04 (envelope `consent_receipts`-tier system record, ring of last 10 000 ids + launch counter) |
| expired / not-yet-valid → reject | same, trusted clock | EXISTS, tested |
| TTL > 300 s → reject at issue | same | EXISTS, tested |
| scope/purpose mismatch → reject | `SecureVault.authorize` | EXISTS, tested |
| clock rollback → effective time never below mark; beyond tolerance reject | `MonotonicGuardClock` | EXISTS, tested; **mark persisted** in P03-04 (same system record) |
| purpose version drift → a grant for v1 does not cover v2 if v2 widened scope | `PurposeRegistry.covers(receipt)` | PLANNED |
| grant without proof → reject | `InteractionGate` | PLANNED |
| grant while scene inactive → reject | `InteractionGate` | PLANNED |
| least privilege: a token covers exactly one scope; `.read` tokens name record ids | `OperationScope.covers` | EXISTS, tested |

## 5. User-facing consent history
Rendered from `ConsentEvent` + `ConsentReceipt`: "Aile isimleri · Sembolik aile merceği · verildi 20 Eki 2026 · geri çekildi —". Shows what each grant allowed, what it derived, and a one-tap revoke. No raw data in the history. Exportable with the backup (it is part of the vault), never anywhere else.

## 6. Audit log that protects privacy
Events carry ids, kinds, timestamps, reason codes — never values, never names, never record contents. Stored as envelopes (encrypted at rest), readable only through `SecureVault` with a `.read` token; crash logs and OS logs get nothing (static scan already forbids logging in vault modules).

## 7. Persistence of the authority (P03-04)
Receipts, events, consumed-token ring and clock mark are records in the same store as personal data (same keys, same backup). Integrity: each is a `RecordEnvelope` (AEAD); the manifest links the latest receipt chain per purpose. Restore: receipts restore with the data; quarantine logic uses the restored receipts, then the user re-confirms (release) — exactly the existing `releaseQuarantine` path.

## 8. Tests to add (P03-04)
grant without proof denied · proof older than 5 s denied · proof while inactive denied · proof reused denied · purpose version widened → old grant does not cover · revoke blocks read and invalidates derived · persisted consumed ring survives relaunch (replay denied after relaunch) · persisted clock mark survives relaunch (rollback across launches denied) · history view shows no payload.
