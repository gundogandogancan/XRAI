// Life Path calculation entry point (constitution §87: calculateLifePath(CivilDate, NumerologyMethodId) → NumerologyTrace).
import XRAIIdentityTime

public enum NumerologyLifePath {
    /// Calculates the Life Path trace for a validated civil date under a registered method.
    ///
    /// - Throws: `NumerologyError.methodUnavailable` when `method` is not in `registry`.
    /// - Note: the result is exact arithmetic with no personality, health or fate meaning.
    public static func calculate(
        _ date: CivilDate,
        method: NumerologyMethodID,
        masterPolicy: MasterNumberPolicy = .preserve11_22_33,
        registry: NumerologyMethodRegistry = .v1
    ) throws -> NumerologyTrace {
        let resolved = try registry.resolve(method)
        let raw = date.decimalDigitsYYYYMMDD

        switch resolved.algorithm {
        case .allDigits:
            let compound = DigitReduction.sum(raw)
            let r = DigitReduction.reduce(compound, policy: masterPolicy)
            return NumerologyTrace(
                methodID: resolved.id,
                masterPolicy: masterPolicy,
                rawDigits: raw,
                componentTraces: nil,
                compound: r.compound,
                reductions: r.steps,
                root: r.root,
                masterNumber: r.masterNumber
            )

        case .components:
            let yearDigits = CivilDate.digits(of: date.year, width: 4)
            let monthDigits = CivilDate.digits(of: date.month, width: 2)
            let dayDigits = CivilDate.digits(of: date.day, width: 2)
            // Method definition (ADR-BOOT-004): each component is reduced starting from its
            // NUMERIC VALUE (1984, 11, 22), not from its digit sum. This is what makes a month of
            // 11 or a day of 22/29 a master-number component under `preserve11_22_33`. Starting
            // from the digit sum instead would be a different method and is deliberately not offered.
            let parts: [(ComponentTrace.Component, [UInt8], Int)] = [
                (.year, yearDigits, date.year), (.month, monthDigits, date.month), (.day, dayDigits, date.day),
            ]
            var traces: [ComponentTrace] = []
            var compound = 0
            for (component, digits, value) in parts {
                let red = DigitReduction.reduce(value, policy: masterPolicy)
                traces.append(ComponentTrace(component: component, digits: digits, reduction: red))
                compound += red.root
            }
            let r = DigitReduction.reduce(compound, policy: masterPolicy)
            return NumerologyTrace(
                methodID: resolved.id,
                masterPolicy: masterPolicy,
                rawDigits: raw,
                componentTraces: traces,
                compound: r.compound,
                reductions: r.steps,
                root: r.root,
                masterNumber: r.masterNumber
            )
        }
    }
}
