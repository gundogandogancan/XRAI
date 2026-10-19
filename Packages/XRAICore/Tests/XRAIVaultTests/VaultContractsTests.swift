import Testing
import XRAIVaultContracts

// Contract-level tests: pure policy, consent, tiers and canonical encoding. No cryptography here.

private let t0: Int64 = 1_760_000_000

@Suite("Privacy tiers and data classes")
struct TierTests {
    @Test("tier order is PUBLIC < PRIVATE < SENSITIVE < HIGH")
    func ordering() {
        #expect(PrivacyTier.publicContent < .devicePrivate)
        #expect(PrivacyTier.devicePrivate < .deviceSensitive)
        #expect(PrivacyTier.deviceSensitive < .deviceHighSensitivity)
    }

    @Test("default tiers follow SECURITY_DATA_EGRESS_MATRIX_v3.2 and decision 6")
    func defaults() {
        #expect(DataClass.parentsNames.defaultTier == .deviceHighSensitivity)
        #expect(DataClass.siblingOrder.defaultTier == .devicePrivate)
        #expect(DataClass.journal.defaultTier == .deviceSensitive)
        #expect(DataClass.psychometrics.defaultTier == .deviceSensitive)
        #expect(DataClass.birthDate.defaultTier == .deviceSensitive)
        #expect(DataClass.goalRoadmap.defaultTier == .devicePrivate)
        for dc in DataClass.allCases { #expect(dc.defaultTier > .publicContent) }
    }

    @Test("family data is third-party information and needs purpose consent")
    func familyData() {
        #expect(DataClass.parentsNames.isThirdPartyInformation)
        #expect(DataClass.siblingOrder.isThirdPartyInformation)
        #expect(DataClass.parentsNames.requiresPurposeConsentToStore)
        #expect(DataClass.siblingOrder.requiresPurposeConsentToStore)
        #expect(!DataClass.birthDate.requiresPurposeConsentToStore)
    }
}

@Suite("Deny-by-default flow policy")
struct PolicyTests {
    private let consent = ConsentReceipt(
        id: "c1",
        scopes: [
            ConsentScope(dataClass: .parentsNames, purpose: "symbolic_family_lens", destination: .deviceVault),
            ConsentScope(dataClass: .journal, purpose: "rich_answer", destination: .perCallConsentedProvider),
        ],
        grantedAtUnixSeconds: t0
    )

    @Test("personal data never reaches analytics, model training, cloud sync or advertising — even with consent")
    func hardRules() {
        let fullConsent = ConsentReceipt(
            id: "c-all",
            scopes: DataClass.allCases.flatMap { dc in Destination.allCases.map { ConsentScope(dataClass: dc, purpose: "any", destination: $0) } },
            grantedAtUnixSeconds: t0
        )
        for dc in DataClass.allCases {
            for dest in VaultPolicy.hardDeniedForPersonalData {
                let d = VaultPolicy.decide(dc, to: dest, consent: fullConsent, purpose: "any", atUnixSeconds: t0 + 1)
                #expect(d == .denied(reason: .hardRule), "\(dc) → \(dest) must be hard-denied")
            }
        }
    }

    @Test("device vault and user-encrypted backup are the only consent-free destinations")
    func defaults() {
        for dc in DataClass.allCases {
            #expect(VaultPolicy.decide(dc, to: .deviceVault, consent: nil, purpose: "", atUnixSeconds: t0).isAllowed)
            #expect(VaultPolicy.decide(dc, to: .userEncryptedBackup, consent: nil, purpose: "", atUnixSeconds: t0).isAllowed)
            #expect(VaultPolicy.decide(dc, to: .perCallConsentedProvider, consent: nil, purpose: "x", atUnixSeconds: t0) == .denied(reason: .consentRequired))
            #expect(VaultPolicy.decide(dc, to: .crashLogs, consent: nil, purpose: "x", atUnixSeconds: t0) == .denied(reason: .consentRequired))
        }
    }

    @Test("provider egress needs an active consent with matching class, purpose and destination")
    func providerConsent() {
        #expect(VaultPolicy.decide(.journal, to: .perCallConsentedProvider, consent: consent, purpose: "rich_answer", atUnixSeconds: t0 + 10).isAllowed)
        #expect(VaultPolicy.decide(.journal, to: .perCallConsentedProvider, consent: consent, purpose: "other_purpose", atUnixSeconds: t0 + 10) == .denied(reason: .consentRequired))
        #expect(VaultPolicy.decide(.birthDate, to: .perCallConsentedProvider, consent: consent, purpose: "rich_answer", atUnixSeconds: t0 + 10) == .denied(reason: .consentRequired))
        // not yet granted
        #expect(VaultPolicy.decide(.journal, to: .perCallConsentedProvider, consent: consent, purpose: "rich_answer", atUnixSeconds: t0 - 1) == .denied(reason: .consentRequired))
    }

    @Test("revocation closes the scope from the revocation instant")
    func revocation() {
        let revoked = consent.revoked(atUnixSeconds: t0 + 100)
        #expect(revoked.isActive(atUnixSeconds: t0 + 99))
        #expect(!revoked.isActive(atUnixSeconds: t0 + 100))
        #expect(VaultPolicy.decide(.journal, to: .perCallConsentedProvider, consent: revoked, purpose: "rich_answer", atUnixSeconds: t0 + 100) == .denied(reason: .consentRequired))
        #expect(revoked.id == consent.id && revoked.scopes == consent.scopes)
    }

    @Test("storing parent names requires a purpose-bound consent; storing a birth date does not")
    func storeGate() {
        #expect(VaultPolicy.mayStore(.parentsNames, consent: nil, purpose: "symbolic_family_lens", atUnixSeconds: t0) == .denied(reason: .consentRequired))
        #expect(VaultPolicy.mayStore(.parentsNames, consent: consent, purpose: "symbolic_family_lens", atUnixSeconds: t0 + 1).isAllowed)
        #expect(VaultPolicy.mayStore(.parentsNames, consent: consent, purpose: "advertising_profile", atUnixSeconds: t0 + 1) == .denied(reason: .consentRequired))
        #expect(VaultPolicy.mayStore(.birthDate, consent: nil, purpose: "", atUnixSeconds: t0).isAllowed)
    }
}

@Suite("Canonical encoding and headers")
struct CanonicalTests {
    @Test("integers round-trip big-endian, strings length-prefixed")
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
    }

    @Test("truncated input throws backupCorrupted, never crashes")
    func truncated() {
        var d = CanonicalDecoder([0x00, 0x00, 0x00, 0x09, 0x41])
        #expect(throws: VaultError.backupCorrupted(reason: "truncated at byte 4")) { _ = try d.readBytes() }
    }

    @Test("header canonical bytes are deterministic and change with every field")
    func headerBytes() {
        let base = RecordDescriptor(recordID: "r1", dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: t0)
        let h1 = EnvelopeHeader(algorithm: .aes256gcm, descriptor: base)
        let h2 = EnvelopeHeader(algorithm: .aes256gcm, descriptor: base)
        #expect(h1.canonicalBytes() == h2.canonicalBytes())
        let variants: [EnvelopeHeader] = [
            EnvelopeHeader(formatVersion: 2, algorithm: .aes256gcm, descriptor: base),
            EnvelopeHeader(algorithm: .aes256gcm, descriptor: RecordDescriptor(recordID: "r2", dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: t0)),
            EnvelopeHeader(algorithm: .aes256gcm, descriptor: RecordDescriptor(recordID: "r1", dataClass: .journal, retention: .untilUserDeletes, createdAtUnixSeconds: t0)),
            EnvelopeHeader(algorithm: .aes256gcm, descriptor: RecordDescriptor(recordID: "r1", dataClass: .birthDate, privacyTier: .deviceHighSensitivity, retention: .untilUserDeletes, createdAtUnixSeconds: t0)),
            EnvelopeHeader(algorithm: .aes256gcm, descriptor: RecordDescriptor(recordID: "r1", dataClass: .birthDate, retention: .sessionOnly, createdAtUnixSeconds: t0)),
            EnvelopeHeader(algorithm: .aes256gcm, descriptor: RecordDescriptor(recordID: "r1", dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: t0 + 1)),
        ]
        for v in variants { #expect(v.canonicalBytes() != h1.canonicalBytes()) }
        #expect(h1.privacyTier == .deviceSensitive, "descriptor defaults tier from data class")
    }

    @Test("constant-time equality")
    func ct() {
        #expect(ConstantTime.equal([1, 2, 3], [1, 2, 3]))
        #expect(!ConstantTime.equal([1, 2, 3], [1, 2, 4]))
        #expect(!ConstantTime.equal([1, 2], [1, 2, 3]))
    }
}

@Suite("Recovery key contract")
struct RecoveryKeyContractTests {
    @Test("rejects wrong length and all-zero keys; description is redacted; display round-trips")
    func basics() throws {
        #expect(throws: VaultError.recoveryKeyInvalid(reason: "expected 32 bytes, got 31")) { try RecoveryKey(bytes: [UInt8](repeating: 7, count: 31)) }
        #expect(throws: VaultError.recoveryKeyInvalid(reason: "all-zero key")) { try RecoveryKey(bytes: [UInt8](repeating: 0, count: 32)) }
        let k = try RecoveryKey(bytes: (0..<32).map { UInt8($0 * 7 % 256) })
        #expect("\(k)" == "RecoveryKey(redacted)")
        #expect(k.displayGroups.count == 8 && k.displayGroups.allSatisfy { $0.count == 8 })
        let parsed = try RecoveryKey.parse(display: k.displayGroups.joined(separator: " - "))
        #expect(parsed == k)
        #expect(throws: VaultError.recoveryKeyInvalid(reason: "wrong length")) { try RecoveryKey.parse(display: "abc") }
    }
}
