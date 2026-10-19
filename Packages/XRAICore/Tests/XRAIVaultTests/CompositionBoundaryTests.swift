import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit

// G2/G5: module and composition boundaries. Includes a real compile-negative check that runs the
// Swift compiler against the built modules, so "not accessible" is proven at compile time, not by
// reflection alone. HONESTY: Swift access control is not a security boundary against malicious code
// inside the same process; these tests prevent accidental misuse and keep the surface explicit.

@Suite("G2 — composition root and module boundary")
struct CompositionBoundaryTests {
    private static func packageRoot() -> URL {
        var u = URL(fileURLWithPath: #filePath)
        u.deleteLastPathComponent(); u.deleteLastPathComponent(); u.deleteLastPathComponent()
        return u
    }

    @Test("Package.swift: no non-test target depends on XRAIVaultTesting; only the adapter and the testing target may import CryptoKit")
    func manifestRule() throws {
        let manifest = try String(contentsOf: Self.packageRoot().appendingPathComponent("Package.swift"), encoding: .utf8)
        // crude but effective: split into target declarations and inspect each
        let decls = manifest.components(separatedBy: ".target(").dropFirst() + manifest.components(separatedBy: ".testTarget(").dropFirst()
        var sawTestingDependency = false
        for d in manifest.components(separatedBy: ".target(").dropFirst() {
            let block = d.components(separatedBy: "),").first ?? d
            if block.contains("\"XRAIVaultTesting\"") && block.contains("dependencies") && !block.contains("name: \"XRAIVaultTesting\"") { sawTestingDependency = true }
            if block.contains("name: \"XRAIVaultKeychain\"") { #expect(!block.contains("XRAIVaultTesting"), "Keychain target must not depend on the testing target") }
        }
        #expect(!sawTestingDependency, "a production target depends on XRAIVaultTesting")
        // Xcode app project (P03-00): the XRAI app target must never link XRAIVaultTesting; only the hosted test target may.
        let projectYML = Self.packageRoot().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("project.yml")
        if let yml = try? String(contentsOf: projectYML, encoding: .utf8), let appRange = yml.range(of: "\n  XRAI:\n") {
            let afterApp = yml[appRange.upperBound...]
            let appBlock = afterApp.range(of: "\n  XRAIHostedTests:").map { afterApp[..<$0.lowerBound] } ?? afterApp
            #expect(!appBlock.contains("XRAIVaultTesting"), "XRAI app target links XRAIVaultTesting")
        }
        #expect(decls.count >= 7)
        let sources = Self.packageRoot().appendingPathComponent("Sources", isDirectory: true)
        for module in ["XRAIIdentityTime", "XRAINumerology", "XRAIVaultContracts"] {
            let dir = sources.appendingPathComponent(module, isDirectory: true)
            guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let u as URL in e where u.pathExtension == "swift" {
                let t = try String(contentsOf: u, encoding: .utf8)
                #expect(!t.contains("import CryptoKit") && !t.contains("import Security") && !t.contains("import Foundation"), Comment(rawValue: "\(module)/\(u.lastPathComponent)"))
            }
        }
    }

    @Test("public surface of SecureVault exposes no key provider, sealer or codec (reflection + source)")
    func vaultSurface() throws {
        let src = try String(contentsOf: Self.packageRoot().appendingPathComponent("Sources/XRAIVaultCryptoKit/SecureVault.swift"), encoding: .utf8)
        #expect(src.contains("private let keyProvider") && src.contains("private let sealer") && src.contains("private let authorizations") && src.contains("private let clock"))
        #expect(!src.contains("public let keyProvider") && !src.contains("public var keyProvider"))
        let sealer = try String(contentsOf: Self.packageRoot().appendingPathComponent("Sources/XRAIVaultCryptoKit/AESGCMEnvelopeSealer.swift"), encoding: .utf8)
        #expect(!sealer.contains("public struct AESGCMEnvelopeSealer") && !sealer.contains("public struct GCMKeyWrapper") && !sealer.contains("class InMemoryKeyProvider"))
        let codec = try String(contentsOf: Self.packageRoot().appendingPathComponent("Sources/XRAIVaultCryptoKit/BackupCodec.swift"), encoding: .utf8)
        #expect(!codec.contains("public enum BackupCodec"))
    }

    #if os(macOS)
    /// Runs `swiftc -typecheck` against the built module interfaces. The positive control must
    /// compile; each negative snippet must fail with an access/lookup error. macOS host only.
    @Test("compile-negative: external code cannot reach AESGCMEnvelopeSealer, BackupCodec, GCMKeyWrapper, SecureVault.keyProvider, or InMemoryKeyProvider via the adapter")
    func compileNegative() throws {
        let root = Self.packageRoot()
        guard let modulesDir = Self.findModulesDir(under: root.appendingPathComponent(".build")) else {
            Issue.record("built .swiftmodule directory not found under .build; run `swift build` first")
            return
        }
        let positive = """
        import XRAIVaultContracts
        import XRAIVaultCryptoKit
        func f(v: SecureVault, e: RecordEnvelope, t: OperationAuthorization) throws -> [UInt8] { try v.open(e, authorization: t) }
        let _ = SystemClock()
        func g(v: SecureVault) -> KeyProtection { v.keyProtection }
        """
        let pos = try Self.typecheck(positive, modulesDir: modulesDir)
        #expect(pos.exit == 0, Comment(rawValue: "positive control failed to compile:\n\(pos.stderr)"))
        guard pos.exit == 0 else { return }

        let negatives: [(String, String)] = [
            ("raw sealer", "import XRAIVaultContracts\nimport XRAIVaultCryptoKit\nfunc f(k: any KeyProvider) { _ = AESGCMEnvelopeSealer(keyProvider: k) }"),
            ("backup codec", "import XRAIVaultContracts\nimport XRAIVaultCryptoKit\nfunc f() throws { _ = try BackupCodec.generateRecoveryKey() }"),
            ("key wrapper", "import XRAIVaultContracts\nimport XRAIVaultCryptoKit\nfunc f() throws { _ = try GCMKeyWrapper(keyID: \"x\", version: 1, material: []) }"),
            ("vault.keyProvider", "import XRAIVaultContracts\nimport XRAIVaultCryptoKit\nfunc f(v: SecureVault) { _ = v.keyProvider }"),
            ("vault.sealer", "import XRAIVaultContracts\nimport XRAIVaultCryptoKit\nfunc f(v: SecureVault) { _ = v.sealer }"),
            ("in-memory provider without the testing module", "import XRAIVaultContracts\nimport XRAIVaultCryptoKit\nfunc f() { _ = InMemoryKeyProvider(keyID: \"x\") }"),
            ("keychain store is internal", "import XRAIVaultContracts\nimport XRAIVaultKeychain\nfunc f() { _ = KeychainStore(service: \"s\", accessibility: .whenUnlockedThisDeviceOnly, mode: .dataProtection) }"),
            ("keychain debug hooks do not exist", "import XRAIVaultContracts\nimport XRAIVaultKeychain\nfunc f(p: KeychainKeyProvider) throws { try p.debugDeleteItem(version: 1) }"),
            ("secure enclave wrapper is internal", "import XRAIVaultContracts\nimport XRAIVaultKeychain\nfunc f() throws { _ = try SecureEnclaveWrapper.wrap(kek: [], accessibility: .whenUnlockedThisDeviceOnly) }"),
        ]
        for (name, code) in negatives {
            let r = try Self.typecheck(code, modulesDir: modulesDir)
            #expect(r.exit != 0, Comment(rawValue: "\(name): compiled but must not"))
            #expect(r.stderr.contains("cannot find") || r.stderr.contains("inaccessible") || r.stderr.contains("is not a member") || r.stderr.contains("has no member") || r.stderr.contains("private"), Comment(rawValue: "\(name): unexpected diagnostics:\n\(r.stderr)"))
        }
    }

    #endif

    private static func findModulesDir(under build: URL) -> URL? {
        guard let e = FileManager.default.enumerator(at: build, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let u as URL in e where u.lastPathComponent == "XRAIVaultCryptoKit.swiftmodule" {
            let parent = u.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.appendingPathComponent("XRAIVaultContracts.swiftmodule").path) { return parent }
        }
        return nil
    }

    #if os(macOS)
    private static func typecheck(_ code: String, modulesDir: URL) throws -> (exit: Int32, stderr: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xrai-compile-neg-\(RecordID().hex)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("snippet.swift")
        try code.write(to: file, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["swiftc", "-typecheck", "-swift-version", "6", "-I", modulesDir.path, file.path]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        let data = err.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
    #endif
}
