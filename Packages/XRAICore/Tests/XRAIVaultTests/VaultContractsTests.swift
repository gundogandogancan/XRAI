import Testing
import XRAIVaultContracts
import XRAIVaultTesting

// Contract-level tests: pure policy, consent authority, tiers, record ids, canonical encoding. No cryptography.

private func desc(_ dc: DataClass, tier: PrivacyTier? = nil, retention: RetentionClass = .untilUserDeletes, purpose: String? = nil) throws -> RecordDescriptor {
    try RecordDescriptor(dataClass: dc, privacyTier: tier, retention: retention, consentPurpose: purpose ?? (dc.requiresPurposeConsentToStore ? "p" : ""), createdAtUnixSeconds: t0)
}

@Suite("Privacy tiers, floors and data classes")
struct TierTests {
    @Test("tier order is PUBLIC < PRIVATE < SENSITIVE < HIGH")
    func ordering() {
        #expect(PrivacyTier.publicContent < .devicePrivate && PrivacyTier.devicePrivate < .deviceSensitive && PrivacyTier.deviceSensitive < .deviceHighSensitivity)
    }

    @Test("floors follow SECURITY_DATA_EGRESS_MATRIX_v3.2 and decision 6; no personal class may be public")
    func floors() {
        #expect(DataClass.parentsNames.minimumTier == .deviceHighSensitivity && DataClass.siblingOrder.minimumTier == .devicePrivate)
        #expect(DataClass.journal.minimumTier == .deviceSensitive && DataClass.psychometrics.minimumTier == .deviceSensitive && DataClass.birthDate.minimumTier == .deviceSensitive)
        for dc in DataClass.allCases { #expect(dc.minimumTier > .publicContent) }
    }

    @Test("descriptor construction fails closed below the floor; consent-gated classes need a non-empty purpose")
    func descriptorFloor() throws {
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .parentsNames, required: .deviceHighSensitivity, got: .publicContent)) { try desc(.parentsNames, tier: .publicContent) }
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .parentsNames, required: .deviceHighSensitivity, got: .deviceSensitive)) { try desc(.parentsNames, tier: .deviceSensitive) }
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .birthDate, required: .deviceSensitive, got: .devicePrivate)) { try desc(.birthDate, tier: .devicePrivate) }
        for dc in DataClass.allCases {
            #expect(throws: VaultError.self) { try desc(dc, tier: .publicContent) }
            #expect(try desc(dc).privacyTier == dc.minimumTier)
            _ = try desc(dc, tier: .deviceHighSensitivity)
        }
        #expect(throws: VaultError.notAuthorized(.consentRequired)) { try desc(.journal, purpose: "") }
        #expect(throws: VaultError.limitExceeded("purpose length")) { try desc(.journal, purpose: String(repeating: "x", count: 129)) }
    }

    @Test("family data is third-party information and needs purpose consent")
    func familyData() {
        #expect(DataClass.parentsNames.isThirdPartyInformation && DataClass.siblingOrder.isThirdPartyInformation)
        #expect(DataClass.parentsNames.requiresPurposeConsentToStore && !DataClass.birthDate.requiresPurposeConsentToStore)
    }
}

@Suite("Deny-by-default flow policy against a consent authority")
struct PolicyTests {
    private var authority: InMemoryConsentAuthority {
        InMemoryConsentAuthority([ConsentReceipt(id: "c1", scopes: [
            ConsentScope(dataClass: .parentsNames, purpose: "symbolic_family_lens", destination: .deviceVault),
            ConsentScope(dataClass: .journal, purpose: "rich_answer", destination: .perCallConsentedProvider),
        ], grantedAtUnixSeconds: t0)])
    }

    @Test("raw personal data never reaches analytics, model training, cloud sync, advertising or crash logs — even with blanket consent")
    func hardRules() {
        let blanket = InMemoryConsentAuthority([ConsentReceipt(id: "c-all", scopes: DataClass.allCases.flatMap { dc in Destination.allCases.map { ConsentScope(dataClass: dc, purpose: "any", destination: $0) } }, grantedAtUnixSeconds: t0)])
        #expect(VaultPolicy.hardDeniedForPersonalData.contains(.crashLogs))
        for dc in DataClass.allCases {
            for dest in VaultPolicy.hardDeniedForPersonalData {
                #expect(VaultPolicy.decide(dc, to: dest, purpose: "any", authority: blanket, atUnixSeconds: t0 + 1) == .denied(reason: .hardRule))
            }
        }
    }

    @Test("device vault and user-encrypted backup are the only consent-free destinations")
    func defaults() {
        let none = NoConsentAuthority()
        for dc in DataClass.allCases {
            #expect(VaultPolicy.decide(dc, to: .deviceVault, purpose: "", authority: none, atUnixSeconds: t0).isAllowed)
            #expect(VaultPolicy.decide(dc, to: .userEncryptedBackup, purpose: "", authority: none, atUnixSeconds: t0).isAllowed)
            #expect(VaultPolicy.decide(dc, to: .perCallConsentedProvider, purpose: "x", authority: none, atUnixSeconds: t0) == .denied(reason: .consentRequired))
        }
    }

    @Test("provider egress needs an active grant held by the AUTHORITY with matching class, purpose and destination")
    func providerConsent() {
        let a = authority
        #expect(VaultPolicy.decide(.journal, to: .perCallConsentedProvider, purpose: "rich_answer", authority: a, atUnixSeconds: t0 + 10).isAllowed)
        #expect(VaultPolicy.decide(.journal, to: .perCallConsentedProvider, purpose: "other", authority: a, atUnixSeconds: t0 + 10) == .denied(reason: .consentRequired))
        #expect(VaultPolicy.decide(.birthDate, to: .perCallConsentedProvider, purpose: "rich_answer", authority: a, atUnixSeconds: t0 + 10) == .denied(reason: .consentRequired))
        #expect(VaultPolicy.decide(.journal, to: .perCallConsentedProvider, purpose: "rich_answer", authority: a, atUnixSeconds: t0 - 1) == .denied(reason: .consentRequired))
    }

    @Test("a caller-held receipt that the authority does not know grants nothing (forged receipt)")
    func forgedReceipt() {
        let forged = ConsentReceipt(id: "forged", scopes: [ConsentScope(dataClass: .parentsNames, purpose: "symbolic_family_lens", destination: .deviceVault)], grantedAtUnixSeconds: t0)
        #expect(forged.covers(.parentsNames, purpose: "symbolic_family_lens", destination: .deviceVault, atUnixSeconds: t0 + 1))
        #expect(VaultPolicy.mayStore(.parentsNames, purpose: "symbolic_family_lens", authority: InMemoryConsentAuthority(), atUnixSeconds: t0 + 1) == .denied(reason: .consentRequired))
    }

    @Test("revocation and expiry close the scope from that instant, for store and for read")
    func revocationAndExpiry() {
        let a = authority
        a.revoke(id: "c1", atUnixSeconds: t0 + 100)
        #expect(VaultPolicy.mayRead(.parentsNames, consentPurpose: "symbolic_family_lens", authority: a, atUnixSeconds: t0 + 99).isAllowed)
        #expect(VaultPolicy.mayRead(.parentsNames, consentPurpose: "symbolic_family_lens", authority: a, atUnixSeconds: t0 + 100) == .denied(reason: .consentRequired))
        let expiring = InMemoryConsentAuthority([ConsentReceipt(id: "e", scopes: [ConsentScope(dataClass: .journal, purpose: "p", destination: .deviceVault)], grantedAtUnixSeconds: t0, expiresAtUnixSeconds: t0 + 50)])
        #expect(VaultPolicy.mayStore(.journal, purpose: "p", authority: expiring, atUnixSeconds: t0 + 49).isAllowed)
        #expect(VaultPolicy.mayStore(.journal, purpose: "p", authority: expiring, atUnixSeconds: t0 + 50) == .denied(reason: .consentRequired))
    }

    @Test("backup inclusion requires user initiation and excludes session-only records")
    func backupGate() {
        #expect(VaultPolicy.mayBackup(.journal, retention: .untilUserDeletes, userInitiated: true).isAllowed)
        #expect(VaultPolicy.mayBackup(.journal, retention: .untilUserDeletes, userInitiated: false) == .denied(reason: .userInitiationRequired))
        #expect(VaultPolicy.mayBackup(.journal, retention: .sessionOnly, userInitiated: true) == .denied(reason: .sessionOnlyNeverPersisted))
    }
}

@Suite("Record ids, canonical encoding and headers")
struct CanonicalTests {
    @Test("record ids are random 128-bit hex, strictly validated, redacted in descriptions")
    func recordIDs() throws {
        var ids = Set<String>()
        for _ in 0..<200 { ids.insert(RecordID().hex) }
        #expect(ids.count == 200)
        let id = RecordID()
        #expect(id.hex.count == 32 && "\(id)" == "RecordID(redacted)" && String(reflecting: id) == "RecordID(redacted)")
        #expect(try RecordID(hex: id.hex) == id)
        #expect(throws: VaultError.invalidRecordID) { try RecordID(hex: "ABCDEF0123456789ABCDEF0123456789") }
        #expect(throws: VaultError.invalidRecordID) { try RecordID(hex: "0123456789abcdef0123456789abcde") }
        #expect(throws: VaultError.invalidRecordID) { try RecordID(hex: "0123456789abcdef0123456789abcdeg") }
        #expect(throws: VaultError.invalidRecordID) { try RecordID(hex: "ayşe-1998-06-30-ayşe-1998-06-30-") }
    }

    @Test("integers round-trip big-endian, strings length-prefixed; truncation throws")
    func roundTrip() throws {
        var e = CanonicalEncoder()
        e.appendU16(0xBEEF); e.appendU32(0xDEADBEEF); e.appendI64(-42); e.appendString("ş ı ğ"); e.appendBytes([1, 2, 3])
        var d = CanonicalDecoder(e.bytes)
        #expect(try d.readU16() == 0xBEEF && (try d.readU32()) == 0xDEADBEEF && (try d.readI64()) == -42)
        #expect(try d.readString() == "ş ı ğ" && (try d.readBytes()) == [1, 2, 3] && d.isAtEnd)
        var t = CanonicalDecoder([0x00, 0x00, 0x00, 0x09, 0x41])
        #expect(throws: VaultError.backupCorrupted(reason: "truncated at byte 4")) { _ = try t.readBytes() }
    }

    @Test("header v2 canonical bytes are deterministic, change with every field incl. purpose; validate() enforces floor and purpose")
    func headerBytes() throws {
        let base = try desc(.birthDate)
        let h1 = EnvelopeHeader(algorithm: .aes256gcm, descriptor: base)
        #expect(h1.formatVersion == 2 && h1.canonicalBytes() == EnvelopeHeader(algorithm: .aes256gcm, descriptor: base).canonicalBytes())
        let variants = [header(h1, version: 1), header(h1, id: RecordID()), header(h1, dc: .goalRoadmap), header(h1, tier: .deviceHighSensitivity),
                        header(h1, ret: .sessionOnly), header(h1, purpose: "x"), header(h1, t: t0 + 1)]
        for v in variants { #expect(v.canonicalBytes() != h1.canonicalBytes()) }
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .parentsNames, required: .deviceHighSensitivity, got: .publicContent)) { try header(h1, dc: .parentsNames, tier: .publicContent, purpose: "p").validate() }
        #expect(throws: VaultError.notAuthorized(.consentRequired)) { try header(h1, dc: .journal, purpose: "").validate() }
        #expect(throws: VaultError.unsupportedFormat(1)) { try header(h1, version: 1).validate() }
        var enc = CanonicalEncoder(); header(h1, dc: .parentsNames, tier: .publicContent, purpose: "p").encode(into: &enc)
        var dec = CanonicalDecoder(enc.bytes)
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .parentsNames, required: .deviceHighSensitivity, got: .publicContent)) { _ = try EnvelopeHeader.decode(from: &dec) }
    }

    @Test("constant-time equality")
    func ct() {
        #expect(ConstantTime.equal([1, 2, 3], [1, 2, 3]) && !ConstantTime.equal([1, 2, 3], [1, 2, 4]) && !ConstantTime.equal([1, 2], [1, 2, 3]))
    }
}

@Suite("Recovery key, operation scopes and error hygiene")
struct RecoveryKeyContractTests {
    @Test("rejects wrong length and all-zero keys; description is redacted; display round-trips")
    func basics() throws {
        #expect(throws: VaultError.recoveryKeyInvalid(reason: "expected 32 bytes, got 31")) { try RecoveryKey(bytes: [UInt8](repeating: 7, count: 31)) }
        #expect(throws: VaultError.recoveryKeyInvalid(reason: "all-zero key")) { try RecoveryKey(bytes: [UInt8](repeating: 0, count: 32)) }
        let k = try RecoveryKey(bytes: (0..<32).map { UInt8($0 * 7 % 256) })
        #expect("\(k)" == "RecoveryKey(redacted)" && k.displayGroups.count == 8)
        #expect(try RecoveryKey.parse(display: k.displayGroups.joined(separator: " - ")) == k)
    }

    @Test("operation scope coverage is exact and record-narrowed")
    func scopes() {
        let a = RecordID(), b = RecordID()
        #expect(OperationScope.read(recordIDs: [a]).covers(.read(recordIDs: nil), recordID: a))
        #expect(!OperationScope.read(recordIDs: [a]).covers(.read(recordIDs: nil), recordID: b))
        #expect(!OperationScope.read(recordIDs: [a]).covers(.read(recordIDs: nil), recordID: nil))
        #expect(OperationScope.read(recordIDs: nil).covers(.read(recordIDs: nil), recordID: b))
        #expect(OperationScope.write(.journal).covers(.write(.journal), recordID: nil) && !OperationScope.write(.journal).covers(.write(.birthDate), recordID: nil))
        #expect(OperationScope.delete(recordIDs: [a, b]).covers(.delete(recordIDs: [a]), recordID: nil) && !OperationScope.delete(recordIDs: [a]).covers(.delete(recordIDs: [a, b]), recordID: nil))
        #expect(OperationScope.maintenance(.rewrap).covers(.maintenance(.rewrap), recordID: nil) && !OperationScope.maintenance(.rewrap).covers(.maintenance(.integrityCheck), recordID: nil))
        #expect(!OperationScope.exportBackup.covers(.restoreBackup, recordID: nil) && !OperationScope.read(recordIDs: nil).covers(.exportBackup, recordID: nil))
        #expect(!OperationScope.maintenance(.integrityCheck).covers(.read(recordIDs: nil), recordID: a), "maintenance never grants plaintext reads")
    }

    @Test("error values and descriptions carry no record id, key id, name or date")
    func errorHygiene() throws {
        let id = RecordID()
        let errors: [VaultError] = [.authenticationFailed, .keyUnavailable(version: 3), .invalidRecordID, .duplicateRecordID, .clockRegressed, .quarantined(.consentRequired),
                                    .privacyTierBelowMinimum(dataClass: .parentsNames, required: .deviceHighSensitivity, got: .publicContent), .authorizationInvalid(.alreadyConsumed),
                                    .notAuthorized(.consentRequired), .limitExceeded("entry count"), .envelopeIntegrityFailed, .backupIntegrityFailed, .backupCorrupted(reason: "bad magic"), .unsupportedFormat(1)]
        for e in errors {
            let s = String(reflecting: e)
            #expect(!s.contains(id.hex) && !s.contains("device-main") && !s.contains("1998"), Comment(rawValue: s))
        }
        let h = EnvelopeHeader(algorithm: .aes256gcm, descriptor: try RecordDescriptor(recordID: id, dataClass: .journal, retention: .untilUserDeletes, consentPurpose: "p", createdAtUnixSeconds: t0))
        let env = RecordEnvelope(header: h, wrappedDEK: WrappedKey(keyID: "device-main", keyVersion: 1, boundRecordID: id, nonce: [], ciphertext: [], tag: []), nonce: [], ciphertext: [], tag: [])
        let s = "\(env)"
        #expect(s.contains("id: <redacted>") && !s.contains(id.hex) && !s.contains("device-main") && !s.contains(String(t0)))
    }
}
