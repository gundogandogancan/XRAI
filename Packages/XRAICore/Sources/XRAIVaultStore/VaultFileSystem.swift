// XRAIVaultStore — P03-04 (ADR-BOOT-009 + Amendment H). File-system port with the exact syscall
// granularity the integrity contracts need (H5): every step of "write temp → fsync → rename →
// fsync dir" is a separate call so a test can inject a crash between any two of them.
// Production uses `RealFileSystem`; the fault-injecting implementation lives in the TEST target only.
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
    /// Creates a new file exclusively (`O_CREAT|O_EXCL|O_NOFOLLOW`, mode 0600, Data Protection complete on iOS).
    func openExclusive(_ path: String) throws -> Int32
    func write(_ fd: Int32, _ bytes: [UInt8]) throws
    /// Durable flush (`F_FULLFSYNC` where available, else `fsync`).
    func sync(_ fd: Int32) throws
    func close(_ fd: Int32) throws
    func rename(_ from: String, _ to: String) throws
    func syncDirectory(_ path: String) throws
    /// Unlink; a missing file is not an error.
    func remove(_ path: String) throws
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
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw VaultError.storeIntegrityFailed(reason: "open for read failed (\(errno))") }
        defer { _ = Darwin.close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { throw VaultError.storeIntegrityFailed(reason: "not a regular file") }
        guard st.st_size <= maxBytes else { throw VaultError.limitExceeded("file size") }
        let total = Int(st.st_size)
        var out = [UInt8](repeating: 0, count: total)
        var done = 0
        while done < total {
            let offset = done
            let n = out.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + offset, total - offset) }
            if n < 0 { throw VaultError.storeIntegrityFailed(reason: "read failed (\(errno))") }
            if n == 0 { break }
            done += n
        }
        guard done == out.count else { throw VaultError.storeIntegrityFailed(reason: "short read") }
        return out
    }

    public func openExclusive(_ path: String) throws -> Int32 {
        #if os(iOS)
        // Create with the protection class first (attributes apply at creation), then open exclusively for writing.
        guard FileManager.default.createFile(atPath: path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600]) else {
            throw VaultError.storeIntegrityFailed(reason: "create failed")
        }
        let fd = open(path, O_WRONLY | O_NOFOLLOW | O_CLOEXEC | O_TRUNC)
        #else
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        #endif
        guard fd >= 0 else { throw VaultError.storeIntegrityFailed(reason: "exclusive create failed (\(errno))") }
        return fd
    }

    public func write(_ fd: Int32, _ bytes: [UInt8]) throws {
        var done = 0
        while done < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + done, bytes.count - done) }
            if n < 0 { throw VaultError.storeIntegrityFailed(reason: "write failed (\(errno))") }
            done += n
        }
    }

    public func sync(_ fd: Int32) throws {
        if fcntl(fd, F_FULLFSYNC) != 0 {
            guard fsync(fd) == 0 else { throw VaultError.storeIntegrityFailed(reason: "fsync failed (\(errno))") }
        }
    }

    public func close(_ fd: Int32) throws {
        guard Darwin.close(fd) == 0 else { throw VaultError.storeIntegrityFailed(reason: "close failed (\(errno))") }
    }

    public func rename(_ from: String, _ to: String) throws {
        guard Darwin.rename(from, to) == 0 else { throw VaultError.storeIntegrityFailed(reason: "rename failed (\(errno))") }
    }

    public func syncDirectory(_ path: String) throws {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw VaultError.storeIntegrityFailed(reason: "open dir failed (\(errno))") }
        defer { _ = Darwin.close(fd) }
        if fcntl(fd, F_FULLFSYNC) != 0 { _ = fsync(fd) }
    }

    public func remove(_ path: String) throws {
        guard unlink(path) == 0 || errno == ENOENT else { throw VaultError.storeIntegrityFailed(reason: "unlink failed (\(errno))") }
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

/// Atomic replace built from the port's steps: temp (exclusive, same directory) → write → fsync →
/// close → rename → fsync(dir). Observers see either the old file or the complete new file.
enum AtomicWriter {
    static func replace(_ fs: any VaultFileSystem, bytes: [UInt8], at path: String, tempName: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        let temp = (dir as NSString).appendingPathComponent(tempName)
        let fd = try fs.openExclusive(temp)
        var closed = false
        defer { if !closed { try? fs.close(fd); try? fs.remove(temp) } }
        try fs.write(fd, bytes)
        try fs.sync(fd)
        try fs.close(fd); closed = true
        try fs.rename(temp, path)
        try fs.syncDirectory(dir)
    }
}
