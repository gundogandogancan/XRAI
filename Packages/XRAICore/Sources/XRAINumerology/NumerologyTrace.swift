// The explainable, redacted result of a Life Path calculation (constitution §87 NumerologyTrace).

/// Sub-trace for one date component under the components method.
public struct ComponentTrace: Hashable, Sendable {
    public enum Component: String, Hashable, Sendable { case year, month, day }
    public let component: Component
    /// Literal digits of this component (zero-padded as in `YYYYMMDD`).
    public let digits: [UInt8]
    public let reduction: ReductionTrace
}

/// Full calculation trace. Every field is derived deterministically from the inputs and the
/// method/policy; nothing here is interpretation, personality or prediction.
public struct NumerologyTrace: Hashable, Sendable {
    /// Epistemic class of every value in this trace (constitution §73).
    public static let epistemicClass = "EXACT_MATH"

    public let methodID: NumerologyMethodID
    public let masterPolicy: MasterNumberPolicy
    /// The eight literal `YYYYMMDD` digits in input order. Contains the date of birth.
    public let rawDigits: [UInt8]
    /// Present only for the components method.
    public let componentTraces: [ComponentTrace]?
    /// Sum before reduction (all digits, or sum of reduced components).
    public let compound: Int
    /// Successive intermediate values after `compound`.
    public let reductions: [Int]
    /// Final value.
    public let root: Int
    /// Set when `root` is a preserved master number.
    public let masterNumber: Int?
    /// FNV-1a 64-bit fingerprint of the canonical trace text. This is an INTEGRITY check for a
    /// stored result, not an anonymizer: the date-of-birth space is small, so the hash is
    /// brute-forceable and must never be logged or used as a pseudonymous identifier.
    public let formulaTraceHash: UInt64

    public init(
        methodID: NumerologyMethodID,
        masterPolicy: MasterNumberPolicy,
        rawDigits: [UInt8],
        componentTraces: [ComponentTrace]?,
        compound: Int,
        reductions: [Int],
        root: Int,
        masterNumber: Int?
    ) {
        self.methodID = methodID
        self.masterPolicy = masterPolicy
        self.rawDigits = rawDigits
        self.componentTraces = componentTraces
        self.compound = compound
        self.reductions = reductions
        self.root = root
        self.masterNumber = masterNumber
        self.formulaTraceHash = TraceHash.fnv1a64(
            NumerologyTrace.canonicalText(
                methodID: methodID, policy: masterPolicy, rawDigits: rawDigits,
                componentTraces: componentTraces, compound: compound, reductions: reductions, root: root
            )
        )
    }

    /// Canonical, order-preserving text that the hash covers. Not for display.
    static func canonicalText(
        methodID: NumerologyMethodID,
        policy: MasterNumberPolicy,
        rawDigits: [UInt8],
        componentTraces: [ComponentTrace]?,
        compound: Int,
        reductions: [Int],
        root: Int
    ) -> String {
        var s = methodID.rawValue + "|" + policy.rawValue + "|"
        for d in rawDigits { s += String(d) }
        s += "|"
        if let cts = componentTraces {
            for ct in cts {
                s += ct.component.rawValue + ":"
                for d in ct.digits { s += String(d) }
                s += ">" + String(ct.reduction.compound)
                for st in ct.reduction.steps { s += ">" + String(st) }
                s += ";"
            }
        }
        s += "|" + String(compound) + "|"
        for r in reductions { s += String(r) + ">" }
        s += "|" + String(root)
        return s
    }
}

extension NumerologyTrace: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacted: shows method, policy and arithmetic outcome but never the raw birth digits.
    public var description: String {
        var s = "NumerologyTrace(method: " + methodID.rawValue
        s += ", policy: " + masterPolicy.rawValue
        s += ", compound: " + String(compound)
        s += ", reductions: ["
        s += reductions.map { String($0) }.joined(separator: ",")
        s += "], root: " + String(root)
        s += ", master: " + (masterNumber.map { String($0) } ?? "nil")
        s += ", rawDigits: <redacted>)"
        return s
    }
    public var debugDescription: String { description }
}

/// Minimal FNV-1a 64-bit, implemented locally so the module needs no hashing framework.
public enum TraceHash {
    public static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
