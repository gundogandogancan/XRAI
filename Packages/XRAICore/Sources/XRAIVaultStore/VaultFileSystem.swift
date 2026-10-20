// XRAIVaultStore — P03-04 (ADR-BOOT-009 + Amendment H), hardened in P03-04H (F-P04-01, F-P04-02).
// File-system port with the exact syscall granularity the integrity contracts need (H5): every step of
// "create temp → write → fsync → close → rename → fsync dir" is a separate call so a test can inject a
// crash or a failed syscall between any two of them.
// Production uses `RealFileSystem`; the fault-injecting implementation lives in the TEST target only.
//
// Durability contract (what is promised and what is not):
// - Every result of every mutating syscall is checked; a failure surfaces as `VaultError.ioFailed` with
//   the step name and errno. No mutation ever reports success before its durable steps returned 0.
// - `F_FULLFSYNC` is requested on file AND directory descriptors; only "not supported here"
//   (ENOTSUP / ENOTTY / EINVAL) falls back to `fsync`, every other errno propagates.
// - EINTR is retried for open/write/fsync/fcntl. `close(2)` is NOT retried on EINTR: XNU releases the
//   descriptor regardless, and a retry could close a reused descriptor; EINTR on close counts as closed.
// - Apple documents F_FULLFSYNC as the flush-to-media request; it does not document directory-fsync
//   semantics on APFS and some storage ignores flush requests. The guarantee claimed here is therefore
//   "every documented durability step was taken and verified", not "survives every power loss".
import Foundation
import XRAIVaultContracts

public enum FileKind: Sendable, Equatable { case missing, regular, directory, symlink, other }

/// Synchronous POSIX-level file operations. Paths are absolute. No path is ever followed through a
/// symbolic link (`O_NOFOLLOW`, `lstat`).
public protocol VaultFileSystem: Sendable {
    func kind(of path: String) throws -> FileKind
    func createDirectory(_ path: String) throws
    func listNames(_ dir: String) throws -> [String]
    /// Reads a REGULAR file without following symlinks. Fails closed on anything else.
    func readRegular(_ path: String, maxBytes: Int) throws -> [UInt8]
    /// P03-04b: opens a REGULAR file for streamed reading (`O_RDONLY|O_NOFOLLOW`, verified with `fstat`); returns the descriptor and the size.
    func openRegularForRead(_ path: String) throws -> (fd: Int32, size: Int64)
    /// One read of up to `maxBytes` (EINTR retried); fewer bytes only at end of file.
    func read(_ fd: Int32, maxBytes: Int) throws -> [UInt8]
    /// Number of directory entries (bounded listing for recovery limits).
    func entryCount(_ dir: String) throws -> Int
    /// Creates a new file exclusively and atomically (`O_CREAT|O_EXCL|O_NOFOLLOW`, mode 0600). A
    /// pre-existing path (file, symlink, anything) is refused untouched. On iOS the descriptor carries
    /// Data Protection "complete" before the first byte is written, verified on the descriptor.
    func openExclusive(_ path: String) throws -> Int32
    func write(_ fd: Int32, _ bytes: [UInt8]) throws
    /// Durable flush (`F_FULLFSYNC`; `fsync` only where F_FULLFSYNC is unsupported). Failures propagate.
    func sync(_ fd: Int32) throws
    func close(_ fd: Int32) throws
    func rename(_ from: String, _ to: String) throws
    /// Durable flush of a directory's entries (same policy as `sync`). Failures propagate.
    func syncDirectory(_ path: String) throws
    /// Unlink; a missing file is not an error.
    func remove(_ path: String) throws
    /// Unlinks `path` only while it still names the inode behind `fd` (the file this writer created with
    /// `openExclusive`). Returns whether anything was removed. Cleanup paths use it so an error never
    /// deletes a file that another writer put at the same name.
    func removeIfOwned(_ path: String, by fd: Int32) throws -> Bool
    func excludeFromBackup(_ path: String) throws
    /// Data Protection class of a path (iOS attribute); nil where unsupported.
    func protectionClass(_ path: String) throws -> String?
    /// Whether a process with this pid exists (stale lock detection).
    func processExists(_ pid: Int32) -> Bool
    var currentPID: Int32 { get }
}

/// Production implementation. Darwin only.
public struct RealFileSystem: VaultFileSystem {
    public init() {}

    /// `NSFileProtectionComplete` as the kernel numbers it (PROTECTION_CLASS_A in XNU's `sys/fcntl.h`;
    /// the fcntl commands `F_GETPROTECTIONCLASS` / `F_SETPROTECTIONCLASS` are public, the class numbers
    /// are not exported to Swift). The mapping 1 ⇔ "NSFileProtectionComplete" is checked on a physical
    /// iPhone by `StoreFileSystemTests.createdFileAttributes` through `FileManager`.
    public static let protectionClassComplete: Int32 = 1

    /// Repeats a syscall while it fails with EINTR.
    @inline(__always)
    static func retryingEINTR(_ op: () -> Int32) -> Int32 {
        while true {
            let r = op()
            if r == -1 && errno == EINTR { continue }
            return r
        }
    }

    public func kind(of path: String) throws -> FileKind {
        var st = stat()
        guard lstat(path, &st) == 0 else { return errno == ENOENT ? .missing : .other }
        switch st.st_mode & S_IFMT {
        case S_IFREG: return .regular
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .other
        }
    }

    public func createDirectory(_ path: String) throws {
        var attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        attrs[.protectionKey] = FileProtectionType.complete
        #endif
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: attrs)
    }

    public func listNames(_ dir: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir).sorted()
    }

    public func readRegular(_ path: String, maxBytes: Int) throws -> [UInt8] {
        let fd = Self.retryingEINTR { open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw VaultError.storeIntegrityFailed(reason: "open for read failed (\(errno))") }
        defer { _ = Darwin.close(fd) }   // read-only descriptor: nothing to flush, the close result carries no data-loss signal
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { throw VaultError.storeIntegrityFailed(reason: "not a regular file") }
        guard st.st_size <= maxBytes else { throw VaultError.limitExceeded("file size") }
        let total = Int(st.st_size)
        var out = [UInt8](repeating: 0, count: total)
        var done = 0
        while done < total {
            let offset = done
            let n = out.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + offset, total - offset) }
            if n < 0 { if errno == EINTR { continue }; throw VaultError.storeIntegrityFailed(reason: "read failed (\(errno))") }
            if n == 0 { break }
            done += n
        }
        guard done == out.count else { throw VaultError.storeIntegrityFailed(reason: "short read") }
        return out
    }

    /// F-P04-01: genuine POSIX exclusive creation on every platform. There is no create-then-open pair,
    /// no truncation, and nothing pre-existing is ever replaced. Before the first byte can be written the
    /// descriptor is checked to be a fresh regular file with one link and mode 0600; on iOS the Data
    /// Protection class is set and read back on the descriptor while the file is still empty, so no
    /// content ever exists under a weaker class. Any failure after creation removes ONLY the inode this
    /// call created (`removeIfOwned`).
    public func openRegularForRead(_ path: String) throws -> (fd: Int32, size: Int64) {
        let fd = Self.retryingEINTR { open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw VaultError.storeIntegrityFailed(reason: "open for read failed (\(errno))") }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { _ = Darwin.close(fd); throw VaultError.storeIntegrityFailed(reason: "not a regular file") }
        return (fd, st.st_size)
    }

    public func read(_ fd: Int32, maxBytes: Int) throws -> [UInt8] {
        guard maxBytes > 0 else { return [] }
        var out = [UInt8](repeating: 0, count: maxBytes)
        var done = 0
        while done < maxBytes {
            let offset = done
            let n = out.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + offset, maxBytes - offset) }
            if n < 0 { if errno == EINTR { continue }; throw VaultError.storeIntegrityFailed(reason: "read failed (\(errno))") }
            if n == 0 { break }
            done += n
        }
        if done < maxBytes { out.removeLast(maxBytes - done) }
        return out
    }

    public func entryCount(_ dir: String) throws -> Int { try FileManager.default.contentsOfDirectory(atPath: dir).count }

    public func openExclusive(_ path: String) throws -> Int32 {
        let fd = Self.retryingEINTR { open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard fd >= 0 else {
            if errno == EEXIST { throw VaultError.storeIntegrityFailed(reason: "exclusive create refused: path exists") }
            throw VaultError.ioFailed(operation: "open", errno: errno)
        }
        do {
            var st = stat()
            guard fstat(fd, &st) == 0 else { throw VaultError.ioFailed(operation: "fstat", errno: errno) }
            guard (st.st_mode & S_IFMT) == S_IFREG, st.st_nlink == 1, st.st_size == 0 else {
                throw VaultError.storeIntegrityFailed(reason: "exclusive create produced an unexpected inode")
            }
            if (st.st_mode & 0o777) != 0o600 {
                guard Self.retryingEINTR({ fchmod(fd, 0o600) }) == 0 else { throw VaultError.ioFailed(operation: "fchmod", errno: errno) }
            }
            #if os(iOS)
            try Self.ensureCompleteProtection(fd)
            #endif
        } catch {
            _ = try? removeIfOwned(path, by: fd)
            _ = Darwin.close(fd)
            throw error
        }
        return fd
    }

    #if os(iOS)
    /// Applies and verifies Data Protection "complete" on an EMPTY descriptor (inherits from the vault
    /// directory in the normal case; set explicitly otherwise). Verification reads the class back from
    /// the descriptor, never from the path.
    static func ensureCompleteProtection(_ fd: Int32) throws {
        if retryingEINTR({ fcntl(fd, F_GETPROTECTIONCLASS) }) != protectionClassComplete {
            guard retryingEINTR({ fcntl(fd, F_SETPROTECTIONCLASS, protectionClassComplete) }) == 0 else {
                throw VaultError.ioFailed(operation: "setprotectionclass", errno: errno)
            }
        }
        guard retryingEINTR({ fcntl(fd, F_GETPROTECTIONCLASS) }) == protectionClassComplete else {
            throw VaultError.storeIntegrityFailed(reason: "data protection class is not complete")
        }
    }
    #endif

    public func write(_ fd: Int32, _ bytes: [UInt8]) throws {
        var done = 0
        while done < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + done, bytes.count - done) }
            if n < 0 { if errno == EINTR { continue }; throw VaultError.ioFailed(operation: "write", errno: errno) }
            if n == 0 { throw VaultError.storeIntegrityFailed(reason: "write made no progress") }
            done += n
        }
    }

    /// F_FULLFSYNC, falling back to fsync ONLY when the file system reports the request unsupported.
    private static func flush(_ fd: Int32, step: String) throws {
        if retryingEINTR({ fcntl(fd, F_FULLFSYNC) }) == 0 { return }
        let e = errno
        guard e == ENOTSUP || e == ENOTTY || e == EINVAL else { throw VaultError.ioFailed(operation: "full" + step, errno: e) }
        guard retryingEINTR({ fsync(fd) }) == 0 else { throw VaultError.ioFailed(operation: step, errno: errno) }
    }

    public func sync(_ fd: Int32) throws { try Self.flush(fd, step: "fsync") }

    public func close(_ fd: Int32) throws {
        guard Darwin.close(fd) == 0 || errno == EINTR else { throw VaultError.ioFailed(operation: "close", errno: errno) }
    }

    public func rename(_ from: String, _ to: String) throws {
        guard Self.retryingEINTR({ Darwin.rename(from, to) }) == 0 else { throw VaultError.ioFailed(operation: "rename", errno: errno) }
    }

    /// F-P04-02: the directory flush result is checked and propagated like a file flush.
    public func syncDirectory(_ path: String) throws {
        let fd = Self.retryingEINTR { open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw VaultError.ioFailed(operation: "opendir", errno: errno) }
        defer { _ = Darwin.close(fd) }   // read-only directory descriptor; the flush result above is what matters
        try Self.flush(fd, step: "dirsync")
    }

    public func remove(_ path: String) throws {
        guard unlink(path) == 0 || errno == ENOENT else { throw VaultError.ioFailed(operation: "unlink", errno: errno) }
    }

    public func removeIfOwned(_ path: String, by fd: Int32) throws -> Bool {
        var mine = stat(), there = stat()
        guard fstat(fd, &mine) == 0 else { throw VaultError.ioFailed(operation: "fstat", errno: errno) }
        guard lstat(path, &there) == 0 else {
            if errno == ENOENT { return false }
            throw VaultError.ioFailed(operation: "lstat", errno: errno)
        }
        guard (there.st_mode & S_IFMT) == S_IFREG, there.st_dev == mine.st_dev, there.st_ino == mine.st_ino else { return false }
        guard unlink(path) == 0 || errno == ENOENT else { throw VaultError.ioFailed(operation: "unlink", errno: errno) }
        return true
    }

    public func excludeFromBackup(_ path: String) throws {
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    public func protectionClass(_ path: String) throws -> String? {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        return (attrs[.protectionKey] as? FileProtectionType)?.rawValue
    }

    public func processExists(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
    public var currentPID: Int32 { getpid() }
}

/// P03-04b: streamed atomic replace — `body` writes pieces through the port to the open descriptor;
/// the same durability tail and cleanup ownership as `replace`. Memory is bounded by what `body` buffers.
extension AtomicWriter {
    static func replaceStreaming(_ fs: any VaultFileSystem, at path: String, tempName: String, body: (Int32) throws -> Void) throws {
        let dir = (path as NSString).deletingLastPathComponent
        let temp = (dir as NSString).appendingPathComponent(tempName)
        let fd = try fs.openExclusive(temp)
        var fdOpen = true
        var renamed = false
        defer {
            if !renamed {
                if fdOpen { _ = try? fs.removeIfOwned(temp, by: fd); try? fs.close(fd) } else { try? fs.remove(temp) }
            }
        }
        try body(fd)
        try fs.sync(fd)
        fdOpen = false
        try fs.close(fd)
        try fs.rename(temp, path)
        renamed = true
        try fs.syncDirectory(dir)
    }
}

/// Atomic replace built from the port's steps: temp (exclusive, same directory) → write → fsync →
/// close → rename → fsync(dir). Observers see either the old file or the complete new file. Every
/// step's result is checked; on failure the temp is removed only while it is provably this writer's
/// inode (before close) or by its private random name (after close); the destination is never touched.
enum AtomicWriter {
    static func replace(_ fs: any VaultFileSystem, bytes: [UInt8], at path: String, tempName: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        let temp = (dir as NSString).appendingPathComponent(tempName)
        let fd = try fs.openExclusive(temp)
        var fdOpen = true
        var renamed = false
        defer {
            if !renamed {
                if fdOpen { _ = try? fs.removeIfOwned(temp, by: fd); try? fs.close(fd) } else { try? fs.remove(temp) }
            }
        }
        try fs.write(fd, bytes)
        try fs.sync(fd)
        fdOpen = false            // XNU releases the descriptor even when close reports an error
        try fs.close(fd)
        try fs.rename(temp, path)
        renamed = true            // the destination now holds the complete file; a failed directory flush propagates
        try fs.syncDirectory(dir)
    }
}
