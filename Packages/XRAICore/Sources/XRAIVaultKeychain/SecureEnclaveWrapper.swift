// Secure Enclave protection of the device KEK (P02-02 GATE 2).
//
// The Secure Enclave does NOT hold arbitrary symmetric AES keys. It holds non-extractable P-256
// keys and performs signing / ECDH key agreement inside the enclave. We therefore protect the
// 32-byte KEK like this (per KEK version):
//   1. create an SE P-256 KeyAgreement key with access control (.privateKeyUsage, ThisDeviceOnly);
//   2. create an ephemeral software P-256 key; ECDH(SE private, ephemeral public) → shared secret;
//   3. HKDF-SHA256(shared, salt, info "xrai.se.kek.v1") → 256-bit wrapping key;
//   4. AES-256-GCM(wrapping key) seals the KEK; store { seKeyBlob, ephemeralPublic, salt, nonce, ct, tag }.
// To unwrap: load the SE key from its blob (only this device's enclave can use it), ECDH with the
// stored ephemeral public key, HKDF, AES-GCM open. The KEK is never stored in the clear and the
// SE key never leaves the hardware. Compromise of the Keychain item alone does not reveal the KEK.
// Availability is checked with `SecureEnclave.isAvailable`; absence is never silently downgraded.
import CryptoKit
import Foundation
import Security
import XRAIVaultContracts

struct SecureEnclaveWrapper {
    static let info = Array("xrai.se.kek.v1".utf8)
    static let blobVersion: UInt16 = 1

    static var isAvailable: Bool { SecureEnclave.isAvailable }

    /// Wraps `kek` under a fresh Secure Enclave key. Returns the opaque blob to store in the Keychain.
    static func wrap(kek: [UInt8], accessibility: KeychainAccessibility) throws -> [UInt8] {
        guard isAvailable else { throw VaultError.secureEnclaveUnavailable }
        var cfError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, accessibility.cfValue, [.privateKeyUsage], &cfError) else {
            throw VaultError.keychainUnavailable(status: errSecParam)
        }
        let seKey: SecureEnclave.P256.KeyAgreement.PrivateKey
        do {
            seKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(compactRepresentable: true, accessControl: access, authenticationContext: nil)
        } catch {
            throw VaultError.secureEnclaveUnavailable
        }
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try seKey.sharedSecretFromKeyAgreement(with: ephemeral.publicKey)
        var salt = [UInt8](repeating: 0, count: 16)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<16 { salt[i] = UInt8.random(in: 0...255, using: &rng) }
        let wrappingKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: info, outputByteCount: 32)
        let nonce = AES.GCM.Nonce()
        let ad = associatedData(seKeyBlob: Array(seKey.dataRepresentation), ephemeralPublic: Array(ephemeral.publicKey.rawRepresentation), salt: salt)
        let box = try AES.GCM.seal(kek, using: wrappingKey, nonce: nonce, authenticating: ad)
        var e = CanonicalEncoder()
        e.appendString("XRAI-SE")
        e.appendU16(blobVersion)
        e.appendBytes(Array(seKey.dataRepresentation))
        e.appendBytes(Array(ephemeral.publicKey.rawRepresentation))
        e.appendBytes(salt)
        e.appendBytes(nonce.withUnsafeBytes { Array($0) })
        e.appendBytes(Array(box.ciphertext))
        e.appendBytes(Array(box.tag))
        return e.bytes
    }

    static func unwrap(blob: [UInt8]) throws -> [UInt8] {
        guard isAvailable else { throw VaultError.secureEnclaveUnavailable }
        var d = CanonicalDecoder(blob)
        guard (try? d.readString()) == "XRAI-SE" else { throw VaultError.keychainCorrupted(reason: "se magic") }
        guard try d.readU16() == blobVersion else { throw VaultError.keychainCorrupted(reason: "se blob version") }
        let seBlob = try d.readBytes()
        let ephPub = try d.readBytes()
        let salt = try d.readBytes()
        let nonce = try d.readBytes()
        let ct = try d.readBytes()
        let tag = try d.readBytes()
        guard d.isAtEnd, salt.count == 16, nonce.count == 12, tag.count == 16, ct.count == 32 else { throw VaultError.keychainCorrupted(reason: "se blob fields") }
        let seKey: SecureEnclave.P256.KeyAgreement.PrivateKey
        do { seKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: Data(seBlob)) } catch { throw VaultError.keychainCorrupted(reason: "se key blob") }
        let pub: P256.KeyAgreement.PublicKey
        do { pub = try P256.KeyAgreement.PublicKey(rawRepresentation: ephPub) } catch { throw VaultError.keychainCorrupted(reason: "ephemeral key") }
        let shared: SharedSecret
        do { shared = try seKey.sharedSecretFromKeyAgreement(with: pub) } catch { throw VaultError.keychainUnavailable(status: errSecAuthFailed) }
        let wrappingKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: info, outputByteCount: 32)
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ct, tag: tag)
            return Array(try AES.GCM.open(box, using: wrappingKey, authenticating: associatedData(seKeyBlob: seBlob, ephemeralPublic: ephPub, salt: salt)))
        } catch {
            throw VaultError.keychainCorrupted(reason: "se unwrap")
        }
    }

    private static func associatedData(seKeyBlob: [UInt8], ephemeralPublic: [UInt8], salt: [UInt8]) -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString("XRAI-SE-AD")
        e.appendBytes(seKeyBlob); e.appendBytes(ephemeralPublic); e.appendBytes(salt)
        return e.bytes
    }
}
