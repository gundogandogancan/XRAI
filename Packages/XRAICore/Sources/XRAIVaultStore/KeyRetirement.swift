// Key-retirement protocol v2 (P03-03H H2): inventory scan, proof, independent verification.
import Foundation
import XRAIVaultContracts
import XRAIVaultCryptoKit

/// Result of a full, read-only inventory of every sealed file in the store directory, parsed by
/// authenticated header only (no decryption, no key use).
public struct StoreInventory: Sendable, Hashable {
    /// key version → number of envelopes wrapped under it (records + system files + journal entries).
    public let countsByVersion: [UInt32: Int]
    /// Orphaned files (never adopted, never opened) by key version — reported, not counted.
    public let orphanCountsByVersion: [UInt32: Int]
    /// SHA-256 over the sorted lines "relative-path|record-id|key-version".
    public let digest: [UInt8]
    public let fileCount: Int
    public let unparsablePaths: [String]
}

/// Proof that no envelope in the store references `keyVersion`, bound to the exact manifest
/// generation and the exclusive maintenance section it was computed in.
public struct KeyRetirementProof: Sendable, Hashable {
    public let keyVersion: UInt32
    public let manifestGeneration: UInt64
    public let manifestHash: [UInt8]
    public let scanDigest: [UInt8]
    public let rewrappedCount: Int
    public let sectionToken: [UInt8]
    public let issuedAtUnixSeconds: Int64
    /// A proof VALUE carries no authority: `forgetRetired` re-checks the section token, generation and hash.
    public init(keyVersion: UInt32, manifestGeneration: UInt64, manifestHash: [UInt8], scanDigest: [UInt8], rewrappedCount: Int, sectionToken: [UInt8], issuedAtUnixSeconds: Int64) {
        self.keyVersion = keyVersion; self.manifestGeneration = manifestGeneration; self.manifestHash = manifestHash; self.scanDigest = scanDigest
        self.rewrappedCount = rewrappedCount; self.sectionToken = sectionToken; self.issuedAtUnixSeconds = issuedAtUnixSeconds
    }
}

/// Read-only verifier. Anyone with read access to the directory can recompute the inventory and
/// compare it with a proof (NT-H2-07).
public enum KeyRetirementVerifier {
    static let maxFileBytes = BackupLimits.maxRecordCiphertextBytes + 2 * BackupLimits.paddingBlockBytes

    public static func inventory(root: String, fileSystem fs: any VaultFileSystem) throws -> StoreInventory {
        var counts: [UInt32: Int] = [:]
        var orphanCounts: [UInt32: Int] = [:]
        var lines: [String] = []
        var unparsable: [String] = []
        var files = 0
        func record(_ rel: String, _ env: RecordEnvelope, orphan: Bool) {
            lines.append(rel + "|" + env.header.recordID.hex + "|" + String(env.wrappedDEK.keyVersion))
            if orphan { orphanCounts[env.wrappedDEK.keyVersion, default: 0] += 1 } else { counts[env.wrappedDEK.keyVersion, default: 0] += 1 }
        }
        for (sub, orphan) in [(StoreLayout.recordsDir, false), (StoreLayout.systemDir, false), (StoreLayout.orphansDir, true)] {
            let dir = (root as NSString).appendingPathComponent(sub)
            guard try fs.kind(of: dir) == .directory else { continue }
            for name in try fs.listNames(dir) where !name.hasPrefix(StoreLayout.tempPrefix) {
                let path = (dir as NSString).appendingPathComponent(name)
                guard try fs.kind(of: path) == .regular else { unparsable.append(sub + "/" + name); continue }
                files += 1
                do {
                    let env = try EnvelopeCodec.decode(try FileFraming.unframe(try fs.readRegular(path, maxBytes: maxFileBytes)))
                    record(sub + "/" + name, env, orphan: orphan)
                } catch { unparsable.append(sub + "/" + name) }
            }
        }
        let jdir = (root as NSString).appendingPathComponent(StoreLayout.journalDir)
        if try fs.kind(of: jdir) == .directory {
            for name in try fs.listNames(jdir) where !name.hasPrefix(StoreLayout.tempPrefix) {
                let path = (jdir as NSString).appendingPathComponent(name)
                guard try fs.kind(of: path) == .regular else { unparsable.append(StoreLayout.journalDir + "/" + name); continue }
                files += 1
                let (entries, _) = FileFraming.unframeJournal(try fs.readRegular(path, maxBytes: maxFileBytes))
                for (i, e) in entries.enumerated() {
                    if let env = try? EnvelopeCodec.decode(e) { record(StoreLayout.journalDir + "/" + name + "#" + String(i), env, orphan: false) }
                    else { unparsable.append(StoreLayout.journalDir + "/" + name + "#" + String(i)) }
                }
            }
        }
        lines.sort()
        let digest = VaultDigest.sha256(Array(lines.joined(separator: "\n").utf8))
        return StoreInventory(countsByVersion: counts, orphanCountsByVersion: orphanCounts, digest: digest, fileCount: files, unparsablePaths: unparsable)
    }

    /// Independent check of a proof against the directory as it is now.
    public static func verify(_ proof: KeyRetirementProof, root: String, fileSystem fs: any VaultFileSystem, currentManifestGeneration: UInt64, currentManifestHash: [UInt8]) throws -> Bool {
        let inv = try inventory(root: root, fileSystem: fs)
        guard inv.unparsablePaths.isEmpty else { return false }
        guard (inv.countsByVersion[proof.keyVersion] ?? 0) == 0 else { return false }
        return inv.digest == proof.scanDigest && proof.manifestGeneration == currentManifestGeneration && ConstantTime.equal(proof.manifestHash, currentManifestHash)
    }
}

public enum StoreLayout {
    public static let recordsDir = "records"
    public static let systemDir = "system"
    public static let journalDir = "journal"
    public static let orphansDir = "orphans"
    public static let manifestFile = "manifest.v1"
    public static let ledgerFile = "ledger.v1"
    public static let authzFile = "authz.v1"
    public static let lockFile = "vault.lock"
    public static let tempPrefix = ".tmp-"
    public static let recordSuffix = ".env"
    public static let journalSuffix = ".j"
}
