# P03_05A_CONSENT_AND_INTERACTION_ARCHITECTURE — the ruling description of purpose, consent and user-interaction authority

**Date:** 2026-10-20 · **Baseline:** `1a3a448` · **Supersedes:** `P03_03_CONSENT_AUTHORITY_SPEC.md` §2, §4 (ring), §5, §7 (see `P03_05A_CANONICAL_RECONCILIATION.md`) · **Status:** implemented at library level + synthetic UI; **not** wired to the production composition root; SECURITY_REVIEWED: NO.

Türkçe özet: Amaçlar sürümlü ve değişmez bir kayıt defterinde (registry) yaşar; izin bir "olay zinciri"dir — verme ve geri çekme eski olayı değiştirmez, yeni olay ekler; etkin izin bu zincirden türetilir. İzin defteri depoda `system/consent.v1` olarak şifreli saklanır, manifeste hash ile bağlanır, silme defteriyle aynı ilan-sonra-yaz kuralıyla korunur. Her işlem yetkisi tek bir dokunuştan doğar: `InteractionGate` etkin sahnede, 5 saniye içinde, tek kullanımlık, tam kapsamlı ve tam amaçlı token üretir; uygulama kodu başka hiçbir yoldan token alamaz. Sınır dürüstçe: süreç içi kötüye kullanım önleme; işletim sistemi sınırı değil, insan niyetinin kriptografik kanıtı değil.

## 1. Objects (contracts, stdlib only — `XRAIVaultContracts/Consent.swift`)

| object | fields | rule |
|---|---|---|
| `PurposeDefinition` | id, version, titleTR/EN, explanationTR/EN, allowedDataClasses, allowedDestinations, retention, derivedPolicy, revocation, sendsToAI | immutable; destinations may never include a hard-denied one; `storeMetadata` never allowed; `covers(later)` = later asks for nothing beyond this |
| `PurposeRegistry` | all versions; `latest(id)`, `definition(id, version)`, `covers(id, grantedVersion, requestedVersion)` | widening (classes, destinations, AI) ⇒ a new version ⇒ old grants do NOT cover; narrowing keeps coverage; unknown version never covers |
| `ConsentEvent` | id, kind {granted, revoked}, purposeID, purposeVersion, dataClasses, destination, atUnixSeconds, authorizationID, revokesEventID?, previousChain | payload-free (no names, no values, no free text beyond the purpose id); canonical encoding; FNV-1a chain value for ORDER evidence (the AEAD around the file is the integrity) |
| `ConsentLedger` | append-only events | `append` refuses wrong chain head, duplicate id, revocation of a non-grant; `activeGrants(at:)` derived by replay; `activeGrant(for:purpose:destination:at:registry:)` applies the version rule |
| `XRAIPurposes.registryV1()` | five shipped purposes (life_path_calculation, symbolic_family_lens, journal_reflection, psychometric_exploration, spiritual_practice_log), all `sendsToAI = false` | shown on the consent screen; a grant records the version shown |

## 2. Persistence (store — `system/consent.v1`)

- Sealed as `storeMetadata` through the system path (no user token needed to read or write it ⇒ **bootstrap solved**: storing a consent event never requires a consent).
- `Manifest.consentHash` (manifest format v3, `XRAI-MANIFEST-3`; v1/v2 refused, never converted) binds the file; `JournalEntry.consentWritten(hash:)` announces the post-state BEFORE the file is replaced; `LedgerBinding.verifyConsent` accepts the file only as the manifest-bound pre-state or the announced post-state (same rule as the deletion ledger, GATE 1 of P03-04b). Otherwise: read-only "consent ledger does not bind to the manifest" / "missing" / "unreadable".
- Mutations: `grantConsent(purposeID:dataClasses:destination:authorization:)` (`.grantConsent(purpose:)` token; registry validation) → op `consent`; `revoke(purpose:mode:)` appends `revoked` events in the SAME mutation as the record consequence. Replay: a `consent` journal commits only an announced, written post-state; otherwise it is dropped and the user re-grants (the event cannot be rebuilt from the journal).
- Authority: `StoreConsentAuthority` (one instance per open; given to the bootstrap vault, the real vault and the actor; published after every commit). The composition chooses it with `VaultComposition(purposeRegistry:…)`; the legacy init with an injected authority remains for tests.
- Backup: `mayBackup(.consentReceipts)` denies; a restored vault has no grants and asks again (NT-CA-06).

## 3. Interaction gate (`XRAIVaultInteraction`)

```
tap / dialog (inside the control's action closure) → gate.mint(kind, purpose)   [scene must be active]
proof (id, kind, purpose, mintedAt) → gate.authorize(scope, purpose, proof)    [≤ 5 s, single use, kind allowed for scope, purpose equal]
→ OperationAuthorization (≤ 300 s TTL, single use) → consumed by SecureVault / FileVaultStore
```
- Required kind per scope: read/write/maintenance → `tap`; export, restore, release, delete, revokeConsent, restoreSuspended, retireKey, admitRestored, activateRestored, reimport, grantConsent → `confirmDialog`.
- Text-field changes and scene transitions have no kind: they cannot mint. Background: neither mint nor authorize.
- The issuer is a `private let` of the gate; `gate.validator` is what the vault/store consume through. Production app code never calls `.issue(`; `AuthorizationIssuer(` appears exactly once, inline inside the gate construction (`TokenSourceScanTests`).
- Trail: payload-free entries (action, proof id, scope description, failure code), capped at 1 000.
- **Limit (verbatim contract):** *It is an in-process misuse prevention mechanism, NOT an operating-system security boundary and NOT cryptographic proof of human intent.* Real boundaries: code signing, App Sandbox, Secure Enclave key usage. High-risk operations (export, delete-all, retire key) are candidates for OS-level user authentication (`LAContext`); see the threat-model note T53 — biometrics are NOT made mandatory without a UX decision and evidence.

## 4. UI contract (synthetic state in P03-05A)

- `ConsentFlow` (app model): purposes from the registry, grant/revoke/delete/suspend/restore as five distinct actions, each needing a proof minted inside the control; re-grant never reactivates; third-party classes have no suspension; eight questions answered per purpose before any grant.
- `ConsentView` / `PurposeDetailView` / `ConsentHistoryView`: identifiers `consent.*`; history shows ids, purpose, classes, time — no content.
- `RestoreRiskPresenter` / `RestoreRiskView`: one explanation per `RestoreRisk` case (8/8), exact-set acknowledgment, no activation for `possiblyDeleted` / `untrustedLocalHistory` (re-import offered), no reset button.
- The screens say "örnek durum / bu sürümde gerçek kayıt yok"; `SecurityStatus.consentRegistryImplemented` stays false until the store is wired (P03-05B).

## 5. Threats this closes / leaves open
Closes: free-text purposes as authority; silent widening of a purpose; editing consent history; consent travelling in backups; tokens minted without a user action (in-process); typing as consent; background issuance; replayed proofs. Leaves open: OS-level user authentication for high-risk operations; consent state of records restored onto a new device (re-ask); the app composition root still uses `NoConsentAuthority` + no store (P03-05B).
