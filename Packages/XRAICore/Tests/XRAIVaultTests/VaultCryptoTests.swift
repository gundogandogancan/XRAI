import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit

// Adversarial tests for the CryptoKit adapter. Every input here is synthetic; no real user data.

private let t0: Int64 = 1_760_000_000
private func desc(_ id: String, _ dc: DataClass = .birthDate) -> RecordDescriptor {
    RecordDescriptor(recordID: id, dataClass: dc, retention: .untilUserDeletes, createdAtUnixSeconds: t0)
}
private func flip(_ bytes: [UInt8], at i: Int) -> [UInt8] { var b = bytes; b[i] ^= 0x01; return b }

@Suite("AES-256-GCM envelope: round trip and structure")
struct SealRoundTripTests {
    @Test("seal/open round-trips for every data class and ciphertext hides the plaintext")
    func roundTrip() throws {
        let sealer = AESGCMEnvelopeSealer(keyProvider: InMemoryKeyProvider(keyID: "device"))
        for dc in DataClass.allCases {
            let plain = Array("synthetic-\(dc.rawValue)-1998-06-30".utf8)
            let env = try sealer.seal(plaintext: plain, descriptor: desc("rec-\(dc.rawValue)", dc))
            #expect(env.header.dataClass == dc && env.header.privacyTier == dc.defaultTier)
            #expect(env.header.algorithm == .aes256gcm && env.header.formatVersion == 1)
            #expect(env.nonce.count == CryptoConstants.gcmNonceBytes)
            #expect(env.tag.count == CryptoConstants.gcmTagBytes)
            #expect(env.ciphertext.count == plain.count)
            #expect(env.ciphertext != plain)
            #expect(!contains(env.ciphertext, Array("1998".utf8)))
            #expect(try sealer.open(env) == plain)
        }
    }

    @Test("empty plaintext is sealed and authenticated too")
    func empty() throws {
        let sealer = AESGCMEnvelopeSealer(keyProvider: InMemoryKeyProvider(keyID: "device"))
        let env = try sealer.seal(plaintext: [], descriptor: desc("empty"))
        #expect(env.ciphertext.isEmpty && env.tag.count == 16)
        #expect(try sealer.open(env) == [])
    }

    @Test("nonce strategy: fresh random nonce per seal; same plaintext never repeats nonce or ciphertext")
    func nonces() throws {
        let sealer = AESGCMEnvelopeSealer(keyProvider: InMemoryKeyProvider(keyID: "device"))
        let plain = Array("same-plaintext".utf8)
        var nonces = Set<[UInt8]>()
        var cts = Set<[UInt8]>()
        var wrapNonces = Set<[UInt8]>()
        for i in 0..<500 {
            let env = try sealer.seal(plaintext: plain, descriptor: desc("n\(i)"))
            nonces.insert(env.nonce); cts.insert(env.ciphertext); wrapNonces.insert(env.wrappedDEK.nonce)
        }
        #expect(nonces.count == 500)
        #expect(cts.count == 500)
        #expect(wrapNonces.count == 500)
    }

    @Test("envelope description is redacted and the type stores no plaintext field")
    func redaction() throws {
        let sealer = AESGCMEnvelopeSealer(keyProvider: InMemoryKeyProvider(keyID: "device"))
        let env = try sealer.seal(plaintext: Array("secret-journal-line".utf8), descriptor: desc("j1", .journal))
        let s = "\(env)"
        #expect(s.contains("payload: <encrypted>") && !s.contains("secret"))
        let labels = Mirror(reflecting: env).children.compactMap { $0.label }
        #expect(labels == ["header", "wrappedDEK", "nonce", "ciphertext", "tag"])
    }
}

@Suite("AES-256-GCM envelope: adversarial")
struct SealAdversarialTests {
    @Test("wrong key provider cannot open")
    func wrongKey() throws {
        let a = AESGCMEnvelopeSealer(keyProvider: InMemoryKeyProvider(keyID: "device"))
        let b = AESGCMEnvelopeSealer(keyProvider: InMemoryKeyProvider(keyID: "device")) // same id, different KEK
        let env = try a.seal(plaintext: Array("x".utf8), descriptor: desc("r"))
        #expect(throws: VaultError.authenticationFailed) { try b.open(env) }
        let c = AESGCMEnvelopeSealer(keyProvider: InMemoryKeyProvider(keyID: "other"))
        #expect(throws: VaultError.keyUnavailable(keyID: "device", version: 1)) { try c.open(env) }
    }

    @Test("tampered ciphertext, tag, nonce or wrapped key fails authentication")
    func tamperBytes() throws {
        let sealer = AESGCMEnvelopeSealer(keyProvider: InMemoryKeyProvider(keyID: "device"))
        let env = try sealer.seal(plaintext: Array("hello vault".utf8), descriptor: desc("r"))
        let h = env.header, w = env.wrappedDEK
        let tampered: [RecordEnvelope] = [
            RecordEnvelope(header: h, wrappedDEK: w, nonce: env.nonce, ciphertext: flip(env.ciphertext, at: 0), tag: env.tag),
            RecordEnvelope(header: h, wrappedDEK: w, nonce: env.nonce, ciphertext: env.ciphertext, tag: flip(env.tag, at: 15)),
            RecordEnvelope(header: h, wrappedDEK: w, nonce: flip(env.nonce, at: 3), ciphertext: env.ciphertext, tag: env.tag),
            RecordEnvelope(header: h, wrappedDEK: WrappedKey(keyID: w.keyID, keyVersion: w.keyVersion, boundRecordID: w.boundRecordID, nonce: w.nonce, ciphertext: flip(w.ciphertext, at: 1), tag: w.tag), nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag),
            RecordEnvelope(header: h, wrappedDEK: WrappedKey(keyID: w.keyID, keyVersion: w.keyVersion, boundRecordID: w.boundRecordID, nonce: w.nonce, ciphertext: w.ciphertext, tag: flip(w.tag, at: 0)), nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag),
        ]
        for t in tampered { #expect(throws: VaultError.authenticationFailed) { try sealer.open(t) } }
        #expect(try sealer.open(env) == Array("hello vault".utf8), "original still opens")
    }

    @Test("tampered authenticated metadata (data class, tier, retention, time, record id) fails")
    func tamperHeader() throws {
        let sealer = AESGCMEnvelopeSealer(keyProvider: InMemoryKeyProvider(keyID: "device"))
        let env = try sealer.seal(plaintext: Array("dob".utf8), descriptor: desc("r", .birthDate))
        let h = env.header
        let headers: [EnvelopeHeader] = [
            EnvelopeHeader(formatVersion: h.formatVersion, algorithm: h.algorithm, recordID: h.recordID, dataClass: .goalRoadmap, privacyTier: h.privacyTier, retention: h.retention, createdAtUnixSeconds: h.createdAtUnixSeconds),
            EnvelopeHeader(formatVersion: h.formatVersion, algorithm: h.algorithm, recordID: h.recordID, dataClass: h.dataClass, privacyTier: .publicContent, retention: h.retention, createdAtUnixSeconds: h.createdAtUnixSeconds),
            EnvelopeHeader(formatVersion: h.formatVersion, algorithm: h.algorithm, recordID: h.recordID, dataClass: h.dataClass, privacyTier: h.privacyTier, retention: .sessionOnly, createdAtUnixSeconds: h.createdAtUnixSeconds),
            EnvelopeHeader(formatVersion: h.formatVersion, algorithm: h.algorithm, recordID: h.recordID, dataClass: h.dataClass, privacyTier: h.privacyTier, retention: h.retention, createdAtUnixSeconds: h.createdAtUnixSeconds + 1),
        ]
        for th in headers {
            let t = RecordEnvelope(header: th, wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag)
            #expect(throws: VaultError.authenticationFailed) { try sealer.open(t) }
        }
        // record id mismatch between header and wrapped key binding is rejected before any crypto
        let th = EnvelopeHeader(formatVersion: h.formatVersion, algorithm: h.algorithm, recordID: "other", dataClass: h.dataClass, privacyTier: h.privacyTier, retention: h.retention, createdAtUnixSeconds: h.createdAtUnixSeconds)
        #expect(throws: VaultError.authenticationFailed) { try sealer.open(RecordEnvelope(header: th, wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag)) }
    }

    @Test("a DEK wrapped for one record cannot be swapped into another record")
    func dekSwap() throws {
        let sealer = AESGCMEnvelopeSealer(keyProvider: InMemoryKeyProvider(keyID: "device"))
        let a = try sealer.seal(plaintext: Array("a".utf8), descriptor: desc("A"))
        let b = try sealer.seal(plaintext: Array("b".utf8), descriptor: desc("B"))
        // forge: take B's wrapped key but relabel it as bound to A
        let forged = WrappedKey(keyID: b.wrappedDEK.keyID, keyVersion: b.wrappedDEK.keyVersion, boundRecordID: "A", nonce: b.wrappedDEK.nonce, ciphertext: b.wrappedDEK.ciphertext, tag: b.wrappedDEK.tag)
        #expect(throws: VaultError.authenticationFailed) { try sealer.open(a.replacingWrappedDEK(forged)) }
    }

    @Test("unsupported format version and malformed lengths are rejected with typed errors")
    func versions() throws {
        let sealer = AESGCMEnvelopeSealer(keyProvider: InMemoryKeyProvider(keyID: "device"))
        let env = try sealer.seal(plaintext: Array("v".utf8), descriptor: desc("r"))
        let h = env.header
        let future = EnvelopeHeader(formatVersion: 99, algorithm: h.algorithm, recordID: h.recordID, dataClass: h.dataClass, privacyTier: h.privacyTier, retention: h.retention, createdAtUnixSeconds: h.createdAtUnixSeconds)
        #expect(throws: VaultError.unsupportedFormat(99)) { try sealer.open(RecordEnvelope(header: future, wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag)) }
        #expect(throws: VaultError.invalidLength(field: "nonce", expected: 12, actual: 11)) { try sealer.open(RecordEnvelope(header: h, wrappedDEK: env.wrappedDEK, nonce: Array(env.nonce.dropLast()), ciphertext: env.ciphertext, tag: env.tag)) }
        #expect(throws: VaultError.invalidLength(field: "tag", expected: 16, actual: 15)) { try sealer.open(RecordEnvelope(header: h, wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: env.ciphertext, tag: Array(env.tag.dropLast()))) }
    }
}

@Suite("Key lifecycle")
struct KeyRotationTests {
    @Test("rotation re-wraps the DEK, payload bytes unchanged; forgotten old version makes un-rewrapped envelopes unreadable")
    func rotate() throws {
        let provider = InMemoryKeyProvider(keyID: "device")
        let sealer = AESGCMEnvelopeSealer(keyProvider: provider)
        let plain = Array("rotate me".utf8)
        let v1 = try sealer.seal(plaintext: plain, descriptor: desc("r"))
        #expect(v1.wrappedDEK.keyVersion == 1)
        let newID = try provider.rotate()
        #expect(newID.version == 2 && provider.currentKey.version == 2)
        #expect(try sealer.open(v1) == plain, "old version still readable before forget")
        let v2 = try sealer.rewrap(v1)
        #expect(v2.wrappedDEK.keyVersion == 2)
        #expect(v2.ciphertext == v1.ciphertext && v2.nonce == v1.nonce && v2.tag == v1.tag && v2.header == v1.header)
        #expect(v2.wrappedDEK != v1.wrappedDEK)
        #expect(try sealer.open(v2) == plain)
        try provider.forget(version: 1)
        #expect(provider.availableVersions == [2])
        #expect(throws: VaultError.keyUnavailable(keyID: "device", version: 1)) { try sealer.open(v1) }
        #expect(try sealer.open(v2) == plain)
        #expect(throws: VaultError.keyUnavailable(keyID: "device", version: 2)) { try provider.forget(version: 2) }
    }
}

@Suite("Portable encrypted backup and device migration")
struct BackupTests {
    private func makeRecords(_ sealer: AESGCMEnvelopeSealer) throws -> ([RecordEnvelope], [[UInt8]]) {
        let plains = [Array("dob:1998-06-30".utf8), Array("journal: synthetic line".utf8), Array("goal: learn".utf8)]
        let classes: [DataClass] = [.birthDate, .journal, .goalRoadmap]
        var envs: [RecordEnvelope] = []
        for (i, p) in plains.enumerated() { envs.append(try sealer.seal(plaintext: p, descriptor: desc("rec\(i)", classes[i]))) }
        return (envs, plains)
    }

    @Test("export → bytes → restore on a NEW device with new device keys; payload ciphertext unchanged; plaintext recovered")
    func migration() throws {
        let oldDevice = InMemoryKeyProvider(keyID: "device-old")
        let oldSealer = AESGCMEnvelopeSealer(keyProvider: oldDevice)
        let (envs, plains) = try makeRecords(oldSealer)
        let rk = try BackupCodec.generateRecoveryKey()
        let backup = try BackupCodec.export(envs, from: oldDevice, recoveryKey: rk, nowUnixSeconds: t0 + 5)
        #expect(backup.entries.count == 3 && backup.salt.count == BackupCodec.saltBytes && backup.integrityTag.count == 32)
        for (b, e) in zip(backup.entries, envs) {
            #expect(b.ciphertext == e.ciphertext && b.nonce == e.nonce && b.tag == e.tag && b.header == e.header)
            #expect(b.wrappedDEK.keyID == PortableBackup.backupKeyID)
            #expect(b.wrappedDEK != e.wrappedDEK)
        }
        let bytes = backup.encode()
        #expect(try PortableBackup.decode(bytes) == backup)
        for p in plains { #expect(!contains(bytes, p), "backup bytes must not contain plaintext") }
        #expect(!contains(bytes, rk.bytes), "backup must not contain the recovery key")

        let newDevice = InMemoryKeyProvider(keyID: "device-new")
        let restored = try BackupCodec.restore(bytes: bytes, recoveryKey: rk, into: newDevice)
        let newSealer = AESGCMEnvelopeSealer(keyProvider: newDevice)
        for (r, p) in zip(restored, plains) {
            #expect(r.wrappedDEK.keyID == "device-new" && r.wrappedDEK.keyVersion == 1)
            #expect(try newSealer.open(r) == p)
        }
        // old device keys are useless for the restored envelopes and vice versa
        #expect(throws: VaultError.keyUnavailable(keyID: "device-new", version: 1)) { try oldSealer.open(restored[0]) }
        #expect(throws: VaultError.keyUnavailable(keyID: "device-old", version: 1)) { try newSealer.open(envs[0]) }
    }

    @Test("wrong recovery key fails integrity; no entry is decrypted")
    func wrongRecoveryKey() throws {
        let dev = InMemoryKeyProvider(keyID: "d")
        let (envs, _) = try makeRecords(AESGCMEnvelopeSealer(keyProvider: dev))
        let rk = try BackupCodec.generateRecoveryKey()
        let backup = try BackupCodec.export(envs, from: dev, recoveryKey: rk, nowUnixSeconds: t0)
        let wrong = try BackupCodec.generateRecoveryKey()
        #expect(wrong != rk)
        #expect(throws: VaultError.backupIntegrityFailed) { try BackupCodec.restore(backup, recoveryKey: wrong, into: InMemoryKeyProvider(keyID: "n")) }
    }

    @Test("corrupted backup: any flipped byte fails integrity or decoding; truncation fails decoding")
    func corrupted() throws {
        let dev = InMemoryKeyProvider(keyID: "d")
        let (envs, _) = try makeRecords(AESGCMEnvelopeSealer(keyProvider: dev))
        let rk = try BackupCodec.generateRecoveryKey()
        let bytes = try BackupCodec.export(envs, from: dev, recoveryKey: rk, nowUnixSeconds: t0).encode()
        let positions = [0, 7, 12, 40, bytes.count / 2, bytes.count - 20, bytes.count - 1]
        for pos in positions {
            let bad = flip(bytes, at: pos)
            do {
                _ = try BackupCodec.restore(bytes: bad, recoveryKey: rk, into: InMemoryKeyProvider(keyID: "n"))
                Issue.record("flip at \(pos) was accepted")
            } catch let e as VaultError {
                switch e {
                case .backupIntegrityFailed, .backupCorrupted, .unsupportedFormat, .unsupportedAlgorithm: break
                default: Issue.record("unexpected error \(e) at \(pos)")
                }
            }
        }
        #expect(throws: VaultError.self) { try PortableBackup.decode(Array(bytes.dropLast(5))) }
        #expect(throws: VaultError.backupCorrupted(reason: "trailing bytes")) { try PortableBackup.decode(bytes + [0]) }
        #expect(throws: VaultError.backupCorrupted(reason: "bad magic")) { try PortableBackup.decode(Array("NOPE".utf8) + bytes) }
    }

    @Test("integrity tag binds entry order and count")
    func reorder() throws {
        let dev = InMemoryKeyProvider(keyID: "d")
        let (envs, _) = try makeRecords(AESGCMEnvelopeSealer(keyProvider: dev))
        let rk = try BackupCodec.generateRecoveryKey()
        let b = try BackupCodec.export(envs, from: dev, recoveryKey: rk, nowUnixSeconds: t0)
        let reordered = PortableBackup(salt: b.salt, createdAtUnixSeconds: b.createdAtUnixSeconds, entries: b.entries.reversed(), integrityTag: b.integrityTag)
        #expect(throws: VaultError.backupIntegrityFailed) { try BackupCodec.restore(reordered, recoveryKey: rk, into: InMemoryKeyProvider(keyID: "n")) }
        let dropped = PortableBackup(salt: b.salt, createdAtUnixSeconds: b.createdAtUnixSeconds, entries: Array(b.entries.dropLast()), integrityTag: b.integrityTag)
        #expect(throws: VaultError.backupIntegrityFailed) { try BackupCodec.restore(dropped, recoveryKey: rk, into: InMemoryKeyProvider(keyID: "n")) }
    }

    @Test("two exports of the same data use different salts and tags; recovery keys are high entropy")
    func salts() throws {
        let dev = InMemoryKeyProvider(keyID: "d")
        let (envs, _) = try makeRecords(AESGCMEnvelopeSealer(keyProvider: dev))
        let rk = try BackupCodec.generateRecoveryKey()
        let b1 = try BackupCodec.export(envs, from: dev, recoveryKey: rk, nowUnixSeconds: t0)
        let b2 = try BackupCodec.export(envs, from: dev, recoveryKey: rk, nowUnixSeconds: t0)
        #expect(b1.salt != b2.salt && b1.integrityTag != b2.integrityTag)
        var keys = Set<[UInt8]>()
        for _ in 0..<50 { keys.insert(try BackupCodec.generateRecoveryKey().bytes) }
        #expect(keys.count == 50)
    }
}

@Suite("Module boundary: CryptoKit only in the adapter")
struct ImportBoundaryTests {
    private static func sources() -> URL {
        var u = URL(fileURLWithPath: #filePath)
        u.deleteLastPathComponent(); u.deleteLastPathComponent(); u.deleteLastPathComponent()
        return u.appendingPathComponent("Sources", isDirectory: true)
    }
    private static func imports(in dir: String) throws -> [String: Set<String>] {
        let root = sources().appendingPathComponent(dir, isDirectory: true)
        var out: [String: Set<String>] = [:]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return out }
        for case let u as URL in e where u.pathExtension == "swift" {
            let text = try String(contentsOf: u, encoding: .utf8)
            var set = Set<String>()
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("import ") { set.insert(String(t.dropFirst(7))) }
            }
            out[u.lastPathComponent] = set
        }
        return out
    }

    @Test("XRAIVaultContracts imports nothing; XRAIVaultCryptoKit imports only CryptoKit, Foundation and the contracts; no other module imports CryptoKit or Security")
    func boundary() throws {
        let contracts = try Self.imports(in: "XRAIVaultContracts")
        #expect(contracts.count >= 4)
        for (f, s) in contracts { #expect(s.isEmpty, "\(f) imports \(s)") }
        let adapter = try Self.imports(in: "XRAIVaultCryptoKit")
        #expect(adapter.count >= 2)
        for (f, s) in adapter { #expect(s.isSubset(of: ["CryptoKit", "Foundation", "XRAIVaultContracts"]), "\(f) imports \(s)") }
        for module in ["XRAIIdentityTime", "XRAINumerology", "XRAIVaultContracts"] {
            for (f, s) in try Self.imports(in: module) {
                #expect(!s.contains("CryptoKit") && !s.contains("Security") && !s.contains("Foundation"), "\(module)/\(f) imports \(s)")
            }
        }
        // No persistence, networking or logging anywhere in the vault modules either.
        for module in ["XRAIVaultContracts", "XRAIVaultCryptoKit"] {
            let root = Self.sources().appendingPathComponent(module, isDirectory: true)
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let u as URL in e where u.pathExtension == "swift" {
                let code = try String(contentsOf: u, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
                    .map { l -> Substring in if let r = l.range(of: "//") { return l[l.startIndex..<r.lowerBound] }; return l }.joined(separator: "\n")
                for token in ["URLSession", "FileManager", "UserDefaults", "print(", "NSLog", "os_log", "Logger(", "write(to", "Data(contentsOf", "String(contentsOf", "NWConnection", "Keychain", "SecItem"] {
                    #expect(!code.contains(token), "\(module)/\(u.lastPathComponent) contains \(token)")
                }
            }
        }
    }
}

/// Naive subsequence search used by the plaintext-leak checks.
private func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard !needle.isEmpty, haystack.count >= needle.count else { return false }
    for i in 0...(haystack.count - needle.count) where haystack[i] == needle[0] {
        if Array(haystack[i..<i + needle.count]) == needle { return true }
    }
    return false
}
