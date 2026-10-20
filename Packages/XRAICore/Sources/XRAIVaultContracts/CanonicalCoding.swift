// Deterministic byte encoding used for authenticated metadata (AEAD associated data) and for the
// portable backup format. Big-endian, length-prefixed, no floating point, no locale.

public struct CanonicalEncoder: Sendable {
    public private(set) var bytes: [UInt8] = []
    public init() {}

    public mutating func appendU8(_ v: UInt8) { bytes.append(v) }
    public mutating func appendU16(_ v: UInt16) { bytes.append(UInt8(v >> 8)); bytes.append(UInt8(v & 0xff)) }
    public mutating func appendU32(_ v: UInt32) {
        bytes.append(UInt8((v >> 24) & 0xff)); bytes.append(UInt8((v >> 16) & 0xff))
        bytes.append(UInt8((v >> 8) & 0xff)); bytes.append(UInt8(v & 0xff))
    }
    public mutating func appendI64(_ v: Int64) {
        let u = UInt64(bitPattern: v)
        var shift: UInt64 = 56
        while true {
            bytes.append(UInt8((u >> shift) & 0xff))
            if shift == 0 { break }
            shift -= 8
        }
    }
    public mutating func appendU64(_ v: UInt64) { appendI64(Int64(bitPattern: v)) }
    public mutating func appendBytes(_ b: [UInt8]) {
        appendU32(UInt32(b.count))
        bytes.append(contentsOf: b)
    }
    public mutating func appendString(_ s: String) { appendBytes(Array(s.utf8)) }
}

public struct CanonicalDecoder {
    private let bytes: [UInt8]
    private var cursor: Int = 0
    public init(_ bytes: [UInt8]) { self.bytes = bytes }

    public var remaining: Int { bytes.count - cursor }
    public var isAtEnd: Bool { cursor == bytes.count }

    private mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard n >= 0, cursor + n <= bytes.count else { throw VaultError.backupCorrupted(reason: "truncated at byte \(cursor)") }
        let s = bytes[cursor..<cursor + n]
        cursor += n
        return s
    }
    public mutating func readU8() throws -> UInt8 { try take(1).first! }
    public mutating func readU16() throws -> UInt16 {
        let s = Array(try take(2)); return UInt16(s[0]) << 8 | UInt16(s[1])
    }
    public mutating func readU32() throws -> UInt32 {
        let s = Array(try take(4))
        return UInt32(s[0]) << 24 | UInt32(s[1]) << 16 | UInt32(s[2]) << 8 | UInt32(s[3])
    }
    public mutating func readI64() throws -> Int64 {
        let s = Array(try take(8))
        var u: UInt64 = 0
        for b in s { u = (u << 8) | UInt64(b) }
        return Int64(bitPattern: u)
    }
    public mutating func readU64() throws -> UInt64 { UInt64(bitPattern: try readI64()) }
    public mutating func readBytes() throws -> [UInt8] {
        let n = Int(try readU32())
        guard n <= 64 * 1024 * 1024 else { throw VaultError.backupCorrupted(reason: "length field too large") }
        return Array(try take(n))
    }
    public mutating func readString() throws -> String {
        let b = try readBytes()
        // `String(decoding:)` repairs invalid sequences; re-encoding and comparing detects them.
        let s = String(decoding: b, as: UTF8.self)
        guard Array(s.utf8) == b else { throw VaultError.backupCorrupted(reason: "invalid utf8") }
        return s
    }
}

/// Constant-time byte comparison so authentication-tag checks do not leak timing.
public enum ConstantTime {
    public static func equal(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var acc: UInt8 = 0
        for i in 0..<a.count { acc |= a[i] ^ b[i] }
        return acc == 0
    }
}
