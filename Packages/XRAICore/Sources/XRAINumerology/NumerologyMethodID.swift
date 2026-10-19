// XRAINumerology — pure, method-versioned numerology (constitution §76, §87).
// Standard library only. No Foundation, no IO.

/// A versioned identifier of a numerology method, e.g. `num.life_path.digits.v1`.
/// The identifier is part of every result; two methods are never conflated into one "number".
public struct NumerologyMethodID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Life Path from the eight literal `YYYYMMDD` digits summed together.
    public static let lifePathDigitsV1 = NumerologyMethodID(rawValue: "num.life_path.digits.v1")
    /// Life Path from year, month and day reduced separately, then summed and reduced.
    public static let lifePathComponentsV1 = NumerologyMethodID(rawValue: "num.life_path.components.v1")
}

/// How 11, 22 and 33 are treated during reduction. Recorded in every trace.
public enum MasterNumberPolicy: String, Hashable, Sendable, CaseIterable {
    /// Always reduce to a single digit 1...9.
    case reduceAll = "reduce_all"
    /// Stop reducing when the compound or an intermediate value is 11, 22 or 33.
    case preserve11_22_33 = "preserve_11_22_33"

    /// The set of values this policy preserves.
    public var preservedValues: Set<Int> {
        switch self {
        case .reduceAll: return []
        case .preserve11_22_33: return [11, 22, 33]
        }
    }
}

/// Typed numerology errors. A valid civil date may still have no registered method (§87).
public enum NumerologyError: Error, Equatable, Sendable {
    case methodUnavailable(NumerologyMethodID)
}

/// The two Life Path algorithm families this module implements.
public enum LifePathAlgorithm: String, Hashable, Sendable {
    case allDigits = "all_digits"
    case components = "year_month_day_components"
}

/// A registered method: identifier, algorithm and an original one-line description.
public struct LifePathMethod: Hashable, Sendable {
    public let id: NumerologyMethodID
    public let algorithm: LifePathAlgorithm
    /// Original wording (not copied from any book) of what the method does.
    public let summary: String
}

/// Immutable registry of known methods. Unknown identifiers throw `methodUnavailable`.
public struct NumerologyMethodRegistry: Sendable {
    private let methods: [NumerologyMethodID: LifePathMethod]

    public init(methods: [LifePathMethod]) {
        var m: [NumerologyMethodID: LifePathMethod] = [:]
        for method in methods { m[method.id] = method }
        self.methods = m
    }

    /// Registry version 1 — the methods verified by BOOT-01 golden tests.
    public static let v1 = NumerologyMethodRegistry(methods: [
        LifePathMethod(
            id: .lifePathDigitsV1,
            algorithm: .allDigits,
            summary: "Sum of the eight literal YYYYMMDD digits, then repeated digit-sum reduction under the chosen master-number policy."
        ),
        LifePathMethod(
            id: .lifePathComponentsV1,
            algorithm: .components,
            summary: "Year, month and day each reduced from their numeric value (e.g. 1984, 11, 22) separately under the policy, summed, then reduced again under the same policy."
        ),
    ])

    public func resolve(_ id: NumerologyMethodID) throws -> LifePathMethod {
        guard let m = methods[id] else { throw NumerologyError.methodUnavailable(id) }
        return m
    }

    public var registeredIDs: [NumerologyMethodID] { methods.keys.sorted { $0.rawValue < $1.rawValue } }
}
