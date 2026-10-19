import Foundation  // test target only: used to read the module's own source files
import Testing
import XRAIIdentityTime
import XRAINumerology

// Constitution §76/§92: "no DOB leak to logs", "negative privacy test asserting this module cannot
// emit network calls or write an unencrypted DOB". The production modules import nothing but the
// Swift standard library, so they have no API surface for IO at all. These tests pin that down.

@Suite("Privacy negative tests — XRAICore production sources")
struct PrivacyNegativeTests {

    private static let forbiddenTokens = [
        "import Foundation", "import Network", "import OSLog", "import os",
        "URLSession", "URLRequest", "FileManager", "UserDefaults", "NSLog", "os_log",
        "print(", "debugPrint(", "Logger(", "CFNetwork", "Socket", "NWConnection",
    ]

    private static func sourcesRoot() -> URL {
        // .../Packages/XRAICore/Tests/XRAINumerologyTests/PrivacyNegativeTests.swift → Packages/XRAICore/Sources
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // XRAINumerologyTests
        url.deleteLastPathComponent() // Tests
        url.deleteLastPathComponent() // XRAICore
        return url.appendingPathComponent("Sources", isDirectory: true)
    }

    /// The pure-math modules. The vault adapter module (XRAIVaultCryptoKit) is covered by its own
    /// stricter import test in XRAIVaultTests; the contracts module is scanned there as stdlib-only too.
    private static let pureMathModules = ["XRAIIdentityTime", "XRAINumerology"]

    private static func productionSwiftFiles() throws -> [URL] {
        let root = sourcesRoot()
        let fm = FileManager.default
        var out: [URL] = []
        for module in pureMathModules {
            let dir = root.appendingPathComponent(module, isDirectory: true)
            guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let u as URL in e where u.pathExtension == "swift" { out.append(u) }
        }
        return out.sorted { $0.path < $1.path }
    }

    @Test("production sources exist for both modules")
    func sourcesPresent() throws {
        let files = try Self.productionSwiftFiles()
        #expect(files.contains { $0.path.hasSuffix("XRAIIdentityTime/CivilDate.swift") })
        #expect(files.contains { $0.path.hasSuffix("XRAINumerology/NumerologyLifePath.swift") })
        #expect(files.count >= 5)
    }

    @Test("no production file imports Foundation/Network/OSLog or references IO, logging or networking APIs")
    func noIOSurface() throws {
        for file in try Self.productionSwiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            // Strip line comments so documentation that names a forbidden API does not trip the scan.
            let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> Substring in
                    if let r = line.range(of: "//") { return line[line.startIndex..<r.lowerBound] }
                    return line
                }
                .joined(separator: "\n")
            for token in Self.forbiddenTokens {
                #expect(!code.contains(token), "\(file.lastPathComponent) contains forbidden token \(token)")
            }
            // Only cross-module import allowed inside the package is XRAIIdentityTime.
            for line in code.split(separator: "\n") where line.trimmingCharacters(in: .whitespaces).hasPrefix("import ") {
                #expect(line.trimmingCharacters(in: .whitespaces) == "import XRAIIdentityTime", "\(file.lastPathComponent): \(line)")
            }
        }
    }

    @Test("trace description and debug description never contain the birth digits")
    func traceRedaction() throws {
        let d = try CivilDate(year: 1998, month: 6, day: 30)
        let t = try NumerologyLifePath.calculate(d, method: .lifePathDigitsV1)
        let printed = "\(t)"
        #expect(printed.contains("num.life_path.digits.v1"))
        #expect(printed.contains("compound: 36"))
        #expect(printed.contains("rawDigits: <redacted>"))
        #expect(!printed.contains("1998"))
        #expect(!printed.contains("19980630"))
        #expect(!printed.contains("0630"))
        #expect(String(reflecting: t) == printed)
        #expect("\(d)" == "CivilDate(redacted)")
    }

    @Test("types are not Codable here: no serialization path for a DOB in the pure module")
    func notCodable() {
        #expect((CivilDate.self as Any) is Encodable.Type == false)
        #expect((NumerologyTrace.self as Any) is Encodable.Type == false)
        #expect((NumerologyTrace.self as Any) is Decodable.Type == false)
    }

    @Test("trace hash is an integrity fingerprint: stable, and distinct for distinct inputs/methods")
    func hashProperties() throws {
        let d = try CivilDate(year: 1998, month: 6, day: 30)
        let a = try NumerologyLifePath.calculate(d, method: .lifePathDigitsV1)
        let b = try NumerologyLifePath.calculate(d, method: .lifePathComponentsV1)
        let c = try NumerologyLifePath.calculate(d, method: .lifePathDigitsV1, masterPolicy: .reduceAll)
        #expect(a.formulaTraceHash == (try NumerologyLifePath.calculate(d, method: .lifePathDigitsV1)).formulaTraceHash)
        #expect(a.formulaTraceHash != b.formulaTraceHash)
        #expect(a.formulaTraceHash != c.formulaTraceHash)
        // Known-answer test for the FNV-1a implementation itself (standard test vectors).
        #expect(TraceHash.fnv1a64("") == 0xcbf2_9ce4_8422_2325)
        #expect(TraceHash.fnv1a64("a") == 0xaf63_dc4c_8601_ec8c)
    }
}
