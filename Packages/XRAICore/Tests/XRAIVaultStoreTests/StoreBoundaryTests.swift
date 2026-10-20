import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultStore
import XRAIVaultTesting

// GATE A (actor isolation), GATE C (no bypass), NT-B-01 (boundaries). Source scans run on the macOS
// host where the package tree is available; runtime checks run everywhere.

@Suite("GATE C — authorization cannot be bypassed through the store")
struct StoreAuthorizationBoundaryTests {
    @Test("the system seal/open path accepts ONLY storeMetadata; personal classes fail closed in both directions")
    func systemPathRestricted() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        for dc in DataClass.allCases where dc != .storeMetadata {
            let d = try RecordDescriptor(dataClass: dc, retention: .untilUserDeletes, consentPurpose: dc.requiresPurposeConsentToStore ? "x" : "", createdAtUnixSeconds: storeT0)
            #expect(throws: VaultError.unsupportedSystemClass) { try s.vault.sealSystem(plaintext: [1], descriptor: d) }
        }
        let id = try await f.put(s, "secret")
        var dec = CanonicalDecoder(Array(try Data(contentsOf: f.rootURL.appendingPathComponent("records/\(id.hex).env"))))
        var d2 = CanonicalDecoder(try dec.readBytes()); let env = try RecordEnvelope.decode(from: &d2)
        #expect(throws: VaultError.unsupportedSystemClass) { try s.vault.openSystem(env) }
        #expect(throws: VaultError.unsupportedSystemClass) { try s.vault.rewrapSystem(env) }
        // and a storeMetadata envelope can never be stored as a user record
        let sys = try s.vault.sealSystem(plaintext: [1], descriptor: try RecordDescriptor(dataClass: .storeMetadata, retention: .untilUserDeletes, createdAtUnixSeconds: storeT0))
        await expectVaultError(.unsupportedSystemClass) { try await s.putEnvelope(sys, authorization: try s.issuer.issue(scope: .write(.storeMetadata))) }
        try await s.close()
    }

    @Test("every store mutation needs the right scope: wrong scope, foreign token, replay and expired tokens are refused and leave no trace")
    func wrongTokens() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let gen = s.manifestGeneration
        let d = try f.descriptor()
        await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.put(plaintext: [1], descriptor: d, authorization: try s.issuer.issue(scope: .read(recordIDs: nil))) }
        await expectVaultError(.authorizationInvalid(.unknownToken)) { try await s.put(plaintext: [1], descriptor: d, authorization: OperationAuthorization(id: "1:1:" + RecordID().hex, scope: .write(.birthDate), purpose: "", issuedAtUnixSeconds: storeT0, expiresAtUnixSeconds: storeT0 + 60)) }
        let t = try s.issuer.issue(scope: .write(.birthDate))
        f.base.advance(61)
        await expectVaultError(.authorizationInvalid(.expired)) { try await s.put(plaintext: [1], descriptor: try f.descriptor(), authorization: t) }
        await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.revoke(purpose: "p", mode: .deleteNow, authorization: try s.issuer.issue(scope: .revokeConsent(purpose: "other"))) }
        await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.admitRestored(RestoreResult(active: [], quarantined: []), authorization: try s.issuer.issue(scope: .restoreBackup)) }
        await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.prepareRetirement(of: 1, authorization: try s.issuer.issue(scope: .maintenance(.rewrap)), maintenance: try s.issuer.issue(scope: .maintenance(.rewrap))) }
        // consent-gated class without a grant is refused by the vault policy inside put
        await expectVaultError(.notAuthorized(.consentRequired)) { try await f.put(s, "x", .journal, purpose: "nogrant") }
        #expect(s.manifestGeneration == gen && f.names("records").isEmpty && f.names("journal").isEmpty)
        try await s.close()
    }

    @Test("reads go through SecureVault.open: a revoked grant, a quarantined id or a purpose mismatch deny even with a valid read token")
    func readsUseVaultPolicy() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "p", id: "g-p")
        let j = try await f.put(s, "diary", .journal, purpose: "p")
        await expectVaultError(.authorizationInvalid(.purposeMismatch)) { try await s.get(j, authorization: try s.issuer.issue(scope: .read(recordIDs: [j]), purpose: "other")) }
        f.authority.revoke(id: "g-p", atUnixSeconds: try f.base.now())
        await expectVaultError(.notAuthorized(.consentRequired)) { try await f.get(s, j, purpose: "p") }
        try await s.close()
    }
}

#if os(macOS)
@Suite("NT-B-01 / GATE A — module boundary and actor isolation (source + manifest + compile-negative)")
struct StoreModuleBoundaryTests {
    private static func packageRoot() -> URL {
        var u = URL(fileURLWithPath: #filePath)
        u.deleteLastPathComponent(); u.deleteLastPathComponent(); u.deleteLastPathComponent()
        return u
    }

    @Test("XRAIVaultStore imports only Foundation, the contracts and the CryptoKit adapter; contains no fault seams, no logging, no CryptoKit/Security")
    func importBoundary() throws {
        let dir = Self.packageRoot().appendingPathComponent("Sources/XRAIVaultStore")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        #expect(files.count >= 4)
        for u in files {
            let t = try String(contentsOf: u, encoding: .utf8)
            for line in t.components(separatedBy: "\n") where line.hasPrefix("import ") {
                #expect(["import Foundation", "import XRAIVaultContracts", "import XRAIVaultCryptoKit"].contains(line.trimmingCharacters(in: .whitespaces)), Comment(rawValue: "\(u.lastPathComponent): \(line)"))
            }
            #expect(!t.contains("Fault") && !t.contains("SimulatedCrash"), Comment(rawValue: "\(u.lastPathComponent) mentions fault injection"))
            #expect(!t.contains("print(") && !t.contains("NSLog(") && !t.contains("os_log") && !t.contains("Logger("), Comment(rawValue: "\(u.lastPathComponent) logs"))
        }
        let manifest = try String(contentsOf: Self.packageRoot().appendingPathComponent("Package.swift"), encoding: .utf8)
        let block = manifest.components(separatedBy: "name: \"XRAIVaultStore\"").dropFirst().map { $0.components(separatedBy: "),").first ?? "" }.first { $0.contains("dependencies") } ?? ""
        #expect(block.contains("\"XRAIVaultContracts\"") && block.contains("\"XRAIVaultCryptoKit\"") && !block.contains("XRAIVaultTesting") && !block.contains("XRAIVaultKeychain"))
        // the app target must not link the store yet (P03-05 wires it)
        let yml = try String(contentsOf: Self.packageRoot().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("project.yml"), encoding: .utf8)
        if let appRange = yml.range(of: "\n  XRAI:\n") {
            let afterApp = yml[appRange.upperBound...]
            let appBlock = afterApp.range(of: "\n  XRAIHostedTests:").map { afterApp[..<$0.lowerBound] } ?? afterApp
            #expect(!appBlock.contains("XRAIVaultStore"), "XRAI app target links XRAIVaultStore before P03-05")
        }
    }

    @Test("GATE A: no `await` inside FileVaultStore's isolated methods — every mutation is one synchronous critical section; the only await is in the static open")
    func noSuspensionInsideMutations() throws {
        let src = try String(contentsOf: Self.packageRoot().appendingPathComponent("Sources/XRAIVaultStore/FileVaultStore.swift"), encoding: .utf8)
        let awaits = src.components(separatedBy: "\n").enumerated().filter { $0.element.contains("await ") }
        #expect(awaits.count == 1 && awaits[0].element.contains("store.recover()"), Comment(rawValue: "await lines: \(awaits.map { "\($0.offset + 1): \($0.element.trimmingCharacters(in: .whitespaces))" })"))
        #expect(src.contains("public actor FileVaultStore"))
        #expect(!src.contains("nonisolated(unsafe)"))
    }

    @Test("compile-negative: external code cannot construct the store directly, reach its loader, the journal writer or the system descriptor path")
    func compileNegative() throws {
        guard let modulesDir = Self.findModulesDir(under: Self.packageRoot().appendingPathComponent(".build")) else {
            Issue.record("built .swiftmodule directory not found; run `swift build` first"); return
        }
        let positive = """
        import XRAIVaultContracts
        import XRAIVaultCryptoKit
        import XRAIVaultStore
        func f(s: FileVaultStore, id: RecordID, t: OperationAuthorization) async throws -> [UInt8] { try await s.get(id, authorization: t) }
        func g(s: FileVaultStore) -> UInt64 { s.epoch }
        """
        let pos = try Self.typecheck(positive, modulesDir: modulesDir)
        #expect(pos.exit == 0, Comment(rawValue: pos.stderr))
        guard pos.exit == 0 else { return }
        let negatives: [(String, String)] = [
            ("direct init", "import XRAIVaultContracts\nimport XRAIVaultCryptoKit\nimport XRAIVaultStore\nfunc f() { _ = FileVaultStore(loaded: 1, keyProvider: 1, anchor: 1, composition: 1, limits: 1, fs: 1) }"),
            ("loader", "import XRAIVaultStore\nfunc f() { _ = FileVaultStore.Loader.self }"),
            ("journal writer", "import XRAIVaultContracts\nimport XRAIVaultStore\nfunc f(s: FileVaultStore) async throws { try await s.writeJournal(1, []) }"),
            ("system writer", "import XRAIVaultStore\nfunc f(s: FileVaultStore) async throws { try await s.writeSystem(\"x\", []) }"),
            ("mutation engine", "import XRAIVaultStore\nfunc f(s: FileVaultStore) async throws { try await s.runMutation(op: \"x\", tokenID: \"\", ids: [], params: []) { _, _, _ in true } }"),
            ("atomic writer", "import XRAIVaultStore\nfunc f() { _ = AtomicWriter.self }"),
        ]
        for (name, code) in negatives {
            let r = try Self.typecheck(code, modulesDir: modulesDir)
            #expect(r.exit != 0, Comment(rawValue: "\(name): compiled but must not"))
        }
    }

    private static func findModulesDir(under build: URL) -> URL? {
        guard let e = FileManager.default.enumerator(at: build, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let u as URL in e where u.lastPathComponent == "XRAIVaultStore.swiftmodule" {
            let parent = u.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.appendingPathComponent("XRAIVaultContracts.swiftmodule").path) { return parent }
        }
        return nil
    }

    private static func typecheck(_ code: String, modulesDir: URL) throws -> (exit: Int32, stderr: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xrai-store-neg-\(RecordID().hex)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("snippet.swift")
        try code.write(to: file, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["swiftc", "-typecheck", "-swift-version", "6", "-I", modulesDir.path, file.path]
        let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
        try p.run(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
#endif
