import Testing
import XRAIVaultContracts

// Contract-level tests: pure policy, consent authority, tiers and canonical encoding. No cryptography.

private let t0: Int64 = 1_760_000_000
private func desc(_ dc: DataClass, tier: PrivacyTier? = nil, retention: RetentionClass = .untilUserDeletes) throws -> RecordDescriptor {
    try RecordDescriptor(dataClass: dc, privacyTier: tier, retention: retention, createdAtUnixSeconds: t0)
}

@Suite("Privacy tiers, floors and data classes")
struct TierTests {
    @Test("tier order is PUBLIC < PRIVATE < SENSITIVE < HIGH")
    func ordering() {
        #expect(PrivacyTier.publicContent < .devicePrivate)
        #expect(PrivacyTier.devicePrivate < .deviceSensitive)
        #expect(PrivacyTier.deviceSensitive < .deviceHighSensitivity)
    }

    @Test("floors follow SECURITY_DATA_EGRESS_MATRIX_v3.2 and decision 6; no personal class may be public")
    func floors() {
        #expect(DataClass.parentsNames.minimumTier == .deviceHighSensitivity)
        #expect(DataClass.siblingOrder.minimumTier == .devicePrivate)
        #expect(DataClass.journal.minimumTier == .deviceSensitive)
        #expect(DataClass.psychometrics.minimumTier == .deviceSensitive)
        #expect(DataClass.birthDate.minimumTier == .deviceSensitive)
        #expect(DataClass.goalRoadmap.minimumTier == .devicePrivate)
        for dc in DataClass.allCases { #expect(dc.minimumTier > .publicContent) }
    }

    @Test("descriptor construction fails closed below the floor and accepts the floor or higher")
    func descriptorFloor() throws {
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .parentsNames, required: .deviceHighSensitivity, got: .publicContent)) {
            try desc(.parentsNames, tier: .publicContent)
        }
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .parentsNames, required: .deviceHighSensitivity, got: .deviceSensitive)) {
            try desc(.parentsNames, tier: .deviceSensitive)
        }
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .birthDate, required: .deviceSensitive, got: .devicePrivate)) {
            try desc(.birthDate, tier: .devicePrivate)
        }
        for dc in DataClass.allCases {
            #expect(throws: VaultError.self) { try desc(dc, tier: .publicContent) }
            let d = try desc(dc)
            #expect(d.privacyTier == dc.minimumTier)
            _ = try desc(dc, tier: .deviceHighSensitivity) // raising is always allowed
        }
    }

    @Test("family data is third-party information and needs purpose consent")
    func familyData() {
        #expect(DataClass.parentsNames.isThirdPartyInformation && DataClass.siblingOrder.isThirdPartyInformation)
        #expect(DataClass.parentsNames.requiresPurposeConsentToStore && DataClass.siblingOrder.requiresPurposeConsentToStore)
        #expect(!DataClass.birthDate.requiresPurposeConsentToStore)
    }
}

@Suite("Deny-by-default flow policy against a consent authority")
struct PolicyTests {
    private let receipt = ConsentReceipt(
        id: "c1",
        scopes: [
            ConsentScope(dataClass: .parentsNames, purpose: "symbolic_family_lens", destination: .deviceVault),
            ConsentScope(dataClass: .journal, purpose: "rich_answer", destination: .perCallConsentedProvider),
        ],
        grantedAtUnixSeconds: t0
    )
    private var authority: InMemoryConsentAuthority { InMemoryConsentAuthority([receipt]) }

    @Test("raw personal data never reaches analytics, model training, cloud sync, advertising or crash logs — even with blanket consent")
    func hardRules() {
        let blanket = InMemoryConsentAuthority([ConsentReceipt(
            id: "c-all",
            scopes: DataClass.allCases.flatMap { dc in Destination.allCases.map { ConsentScope(dataClass: dc, purpose: "any", destination: $0) } },
            grantedAtUnixSeconds: t0
        )])
        #expect(VaultPolicy.hardDeniedForPersonalData.contains(.crashLogs))
        for dc in DataClass.allCases {
            for dest in VaultPolicy.hardDeniedForPersonalData {
                #expect(VaultPolicy.decide(dc, to: dest, purpose: "any", authority: blanket, atUnixSeconds: t0 + 1) == .denied(reason: .hardRule), "\(dc) → \(dest)")
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
            #expect(VaultPolicy.decide(dc, to: .appleStoreKit, purpose: "x", authority: none, atUnixSeconds: t0) == .denied(reason: .consentRequired))
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
        #expect(forged.covers(.parentsNames, purpose: "symbolic_family_lens", destination: .deviceVault, atUnixSeconds: t0 + 1), "the value itself looks valid")
        let a = InMemoryConsentAuthority() // authority never saw it
        #expect(VaultPolicy.mayStore(.parentsNames, purpose: "symbolic_family_lens", authority: a, atUnixSeconds: t0 + 1) == .denied(reason: .consentRequired))
    }

    @Test("revocation and expiry close the scope from that instant")
    func revocationAndExpiry() {
        let a = authority
        a.revoke(id: "c1", atUnixSeconds: t0 + 100)
        #expect(VaultPolicy.mayStore(.parentsNames, purpose: "symbolic_family_lens", authority: a, atUnixSeconds: t0 + 99).isAllowed)
        #expect(VaultPolicy.mayStore(.parentsNames, purpose: "symbolic_family_lens", authority: a, atUnixSeconds: t0 + 100) == .denied(reason: .consentRequired))
        let expiring = InMemoryConsentAuthority([ConsentReceipt(id: "e", scopes: [ConsentScope(dataClass: .journal, purpose: "p", destination: .deviceVault)], grantedAtUnixSeconds: t0, expiresAtUnixSeconds: t0 + 50)])
        #expect(VaultPolicy.mayStore(.journal, purpose: "p", authority: expiring, atUnixSeconds: t0 + 49).isAllowed)
        #expect(VaultPolicy.mayStore(.journal, purpose: "p", authority: expiring, atUnixSeconds: t0 + 50) == .denied(reason: .consentRequired))
    }

    @Test("storing parent names requires a purpose-bound grant; storing a birth date does not")
    func storeGate() {
        let a = authority
        #expect(VaultPolicy.mayStore(.parentsNames, purpose: "symbolic_family_lens", authority: InMemoryConsentAuthority(), atUnixSeconds: t0) == .denied(reason: .consentRequired))
        #expect(VaultPolicy.mayStore(.parentsNames, purpose: "symbolic_family_lens", authority: a, atUnixSeconds: t0 + 1).isAllowed)
        #expect(VaultPolicy.mayStore(.parentsNames, purpose: "advertising_profile", authority: a, atUnixSeconds: t0 + 1) == .denied(reason: .consentRequired))
        #expect(VaultPolicy.mayStore(.birthDate, purpose: "", authority: NoConsentAuthority(), atUnixSeconds: t0).isAllowed)
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
        #expect(id.hex.count == 32)
        #expect("\(id)" == "RecordID(redacted)" && String(reflecting: id) == "RecordID(redacted)")
        #expect(try RecordID(hex: id.hex) == id)
        #expect(throws: VaultError.invalidRecordID) { try RecordID(hex: "ABCDEF0123456789ABCDEF0123456789") } // upper case
        #expect(throws: VaultError.invalidRecordID) { try RecordID(hex: "0123456789abcdef0123456789abcde") }  // 31 chars
        #expect(throws: VaultError.invalidRecordID) { try RecordID(hex: "0123456789abcdef0123456789abcdeg") } // non-hex
        #expect(throws: VaultError.invalidRecordID) { try RecordID(hex: "ayşe-1998-06-30-ayşe-1998-06-30-") } // name/date shaped
    }

    @Test("integers round-trip big-endian, strings length-prefixed; truncation throws")
    func roundTrip() throws {
        var e = CanonicalEncoder()
        e.appendU16(0xBEEF); e.appendU32(0xDEADBEEF); e.appendI64(-42); e.appendString("ş ı ğ"); e.appendBytes([1, 2, 3])
        var d = CanonicalDecoder(e.bytes)
        #expect(try d.readU16() == 0xBEEF)
        #expect(try d.readU32() == 0xDEADBEEF)
        #expect(try d.readI64() == -42)
        #expect(try d.readString() == "ş ı ğ")
        #expect(try d.readBytes() == [1, 2, 3])
        #expect(d.isAtEnd)
        var t = CanonicalDecoder([0x00, 0x00, 0x00, 0x09, 0x41])
        #expect(throws: VaultError.backupCorrupted(reason: "truncated at byte 4")) { _ = try t.readBytes() }
    }

    @Test("header canonical bytes are deterministic and change with every field; validate() enforces the floor")
    func headerBytes() throws {
        let base = try desc(.birthDate)
        let h1 = EnvelopeHeader(algorithm: .aes256gcm, descriptor: base)
        #expect(h1.canonicalBytes() == EnvelopeHeader(algorithm: .aes256gcm, descriptor: base).canonicalBytes())
        let variants: [EnvelopeHeader] = [
            EnvelopeHeader(formatVersion: 2, algorithm: .aes256gcm, descriptor: base),
            EnvelopeHeader(algorithm: .aes256gcm, descriptor: try RecordDescriptor(dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: t0)),
            EnvelopeHeader(algorithm: .aes256gcm, descriptor: try RecordDescriptor(recordID: base.recordID, dataClass: .journal, retention: .untilUserDeletes, createdAtUnixSeconds: t0)),
            EnvelopeHeader(algorithm: .aes256gcm, descriptor: try RecordDescriptor(recordID: base.recordID, dataClass: .birthDate, privacyTier: .deviceHighSensitivity, retention: .untilUserDeletes, createdAtUnixSeconds: t0)),
            EnvelopeHeader(algorithm: .aes256gcm, descriptor: try RecordDescriptor(recordID: base.recordID, dataClass: .birthDate, retention: .sessionOnly, createdAtUnixSeconds: t0)),
            EnvelopeHeader(algorithm: .aes256gcm, descriptor: try RecordDescriptor(recordID: base.recordID, dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: t0 + 1)),
        ]
        for v in variants { #expect(v.canonicalBytes() != h1.canonicalBytes()) }
        let downgraded = EnvelopeHeader(formatVersion: 1, algorithm: .aes256gcm, recordID: base.recordID, dataClass: .parentsNames, privacyTier: .publicContent, retention: .untilUserDeletes, createdAtUnixSeconds: t0)
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .parentsNames, required: .deviceHighSensitivity, got: .publicContent)) { try downgraded.validate() }
        var enc = CanonicalEncoder(); downgraded.encode(into: &enc)
        var dec = CanonicalDecoder(enc.bytes)
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .parentsNames, required: .deviceHighSensitivity, got: .publicContent)) { _ = try EnvelopeHeader.decode(from: &dec) }
    }

    @Test("constant-time equality")
    func ct() {
        #expect(ConstantTime.equal([1, 2, 3], [1, 2, 3]))
        #expect(!ConstantTime.equal([1, 2, 3], [1, 2, 4]))
        #expect(!ConstantTime.equal([1, 2], [1, 2, 3]))
    }
}

@Suite("Recovery key and error hygiene")
struct RecoveryKeyContractTests {
    @Test("rejects wrong length and all-zero keys; description is redacted; display round-trips")
    func basics() throws {
        #expect(throws: VaultError.recoveryKeyInvalid(reason: "expected 32 bytes, got 31")) { try RecoveryKey(bytes: [UInt8](repeating: 7, count: 31)) }
        #expect(throws: VaultError.recoveryKeyInvalid(reason: "all-zero key")) { try RecoveryKey(bytes: [UInt8](repeating: 0, count: 32)) }
        let k = try RecoveryKey(bytes: (0..<32).map { UInt8($0 * 7 % 256) })
        #expect("\(k)" == "RecoveryKey(redacted)")
        #expect(k.displayGroups.count == 8 && k.displayGroups.allSatisfy { $0.count == 8 })
        #expect(try RecoveryKey.parse(display: k.displayGroups.joined(separator: " - ")) == k)
        #expect(throws: VaultError.recoveryKeyInvalid(reason: "wrong length")) { try RecoveryKey.parse(display: "abc") }
    }

    @Test("error values and descriptions carry no record id, key id, name or date")
    func errorHygiene() throws {
        let id = RecordID()
        let errors: [VaultError] = [.authenticationFailed, .keyUnavailable(version: 3), .invalidRecordID, .duplicateRecordID,
                                    .privacyTierBelowMinimum(dataClass: .parentsNames, required: .deviceHighSensitivity, got: .publicContent),
                                    .notAuthorized(.consentRequired), .limitExceeded("entry count"), .envelopeIntegrityFailed,
                                    .backupIntegrityFailed, .backupCorrupted(reason: "bad magic"), .unsupportedFormat(1)]
        for e in errors {
            let s = String(reflecting: e)
            // "device" alone appears legitimately in tier names (DEVICE_ONLY_*); key ids like "device-main" must not.
            #expect(!s.contains(id.hex) && !s.contains("device-main") && !s.contains("1998"), Comment(rawValue: s))
        }
        let h = EnvelopeHeader(algorithm: .aes256gcm, descriptor: try RecordDescriptor(recordID: id, dataClass: .journal, retention: .untilUserDeletes, createdAtUnixSeconds: t0))
        let env = RecordEnvelope(header: h, wrappedDEK: WrappedKey(keyID: "device-main", keyVersion: 1, boundRecordID: id, nonce: [], ciphertext: [], tag: []), nonce: [], ciphertext: [], tag: [])
        let s = "\(env)"
        #expect(s.contains("id: <redacted>") && !s.contains(id.hex) && !s.contains("device-main") && !s.contains(String(t0)))
    }
}
