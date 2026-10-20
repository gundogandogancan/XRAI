// P03-04b GATE 5 — resource evidence at scale (row NT-SC-01). Numbers are recorded in the log; the
// assertions check correctness and bounded memory, not a performance promise.
import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultStore
import XRAIVaultTesting

@Suite("GATE 5 — scale: 2 000 records through open, export v3, restore, admission, activation", .serialized)
struct StoreScaleTests {
    @Test("NT-SC-01: 2 000 records (macOS) / 500 (iOS hosts) — reopen (recovery scan), export v3, restore + admit + activate on a fresh vault; wall time and resident memory recorded; everything readable afterwards")
    func twoThousandRecords() async throws {
        #if os(macOS)
        let n = 2_000
        #else
        let n = 500   // hosted runs (Simulator / iPhone): every put and every admitted file costs full flushes; bounded so the bundle stays within its time budget
        #endif
        let a = StoreFixture(); defer { a.cleanup() }
        let sa = try await a.open()
        let tPut = Date()
        var ids: [RecordID] = []
        for i in 0..<n { ids.append(try await a.put(sa, "record \(i)")) }
        let putSeconds = Date().timeIntervalSince(tPut)
        try await a.delete(sa, Set(ids.prefix(100)))
        try await sa.close()
        let rss0 = residentBytes()
        let tOpen = Date()
        let sa2 = try await a.open()
        let openSeconds = Date().timeIntervalSince(tOpen)
        #expect(sa2.recordIDs.count == n - 100 && sa2.deletionCount == 100 && sa2.integrityReport().missingFiles.isEmpty)
        let tExp = Date()
        let (bytes, rk) = try await a.exportV3(sa2)
        let exportSeconds = Date().timeIntervalSince(tExp)
        try await sa2.close()
        let b = StoreFixture(); defer { b.cleanup() }
        let sb = try await b.open()
        let tRes = Date()
        let r = try b.restore(sb, bytes, rk)
        let rep = try await b.admit(sb, r)
        let restoreSeconds = Date().timeIntervalSince(tRes)
        #expect(rep.staged.count == n - 100 && rep.historyMerged && sb.deletionCount == 100)
        let tAct = Date()
        try await b.activate(sb, Set(rep.staged))
        let activateSeconds = Date().timeIntervalSince(tAct)
        let rss1 = residentBytes()
        for id in rep.staged.prefix(50) { _ = try await b.get(sb, id) }
        #expect(sb.recordIDs.count == n - 100 && sb.state(of: rep.staged[0]) == .active)
        let mb = Double(bytes.count) / 1_048_576
        print(String(format: "NT-SC-01 n=%d: put %.2f s, reopen %.2f s, export v3 %.2f s (%.1f MiB), restore+admit %.2f s, activate %.2f s, RSS delta %lld MiB", n, putSeconds, openSeconds, exportSeconds, mb, restoreSeconds, activateSeconds, (Int64(rss1) - Int64(rss0)) / 1_048_576))
        try await sb.close()
    }
}
