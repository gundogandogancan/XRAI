// Exact integer digit arithmetic with an explainable trace. Standard library only.

/// The result of reducing one integer under a master-number policy.
public struct ReductionTrace: Hashable, Sendable {
    /// The value reduction started from.
    public let compound: Int
    /// Successive intermediate values after `compound` (empty when no reduction happened).
    public let steps: [Int]
    /// The final value: 1...9, or a preserved master number under `preserve11_22_33`.
    public let root: Int
    /// Set only when `root` is a preserved master number.
    public let masterNumber: Int?
    public let policy: MasterNumberPolicy
}

public enum DigitReduction {
    /// Sum of the decimal digits of a non-negative integer.
    public static func digitSum(_ n: Int) -> Int {
        precondition(n >= 0, "digitSum is defined for non-negative integers")
        var v = n
        var s = 0
        while v > 0 {
            s += v % 10
            v /= 10
        }
        return s
    }

    /// Sum of an explicit digit sequence.
    public static func sum(_ digits: [UInt8]) -> Int {
        var s = 0
        for d in digits {
            precondition(d <= 9, "a decimal digit must be 0...9")
            s += Int(d)
        }
        return s
    }

    /// Reduce `compound` by repeated digit-sum until a single digit, or until a value preserved
    /// by `policy` is reached. The trace records every intermediate value.
    public static func reduce(_ compound: Int, policy: MasterNumberPolicy) -> ReductionTrace {
        precondition(compound >= 0, "reduce is defined for non-negative integers")
        var steps: [Int] = []
        var v = compound
        let preserved = policy.preservedValues
        while v > 9 {
            if preserved.contains(v) { break }
            v = digitSum(v)
            steps.append(v)
        }
        let master = preserved.contains(v) ? v : nil
        return ReductionTrace(compound: compound, steps: steps, root: v, masterNumber: master, policy: policy)
    }
}
