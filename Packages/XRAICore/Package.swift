// swift-tools-version: 6.0
// XRAICore — the smallest executable pure core of XRAI (constitution §86, §89 P01).
// No UI, no networking, no storage, no analytics, no model dependency.
import PackageDescription

let package = Package(
    name: "XRAICore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "XRAIIdentityTime", targets: ["XRAIIdentityTime"]),
        .library(name: "XRAINumerology", targets: ["XRAINumerology"]),
        .library(name: "XRAIVaultContracts", targets: ["XRAIVaultContracts"]),
        .library(name: "XRAIVaultCryptoKit", targets: ["XRAIVaultCryptoKit"]),
    ],
    targets: [
        .target(
            name: "XRAIIdentityTime",
            dependencies: []
        ),
        .target(
            name: "XRAINumerology",
            dependencies: ["XRAIIdentityTime"]
        ),
        .testTarget(
            name: "XRAIIdentityTimeTests",
            dependencies: ["XRAIIdentityTime"]
        ),
        .testTarget(
            name: "XRAINumerologyTests",
            dependencies: ["XRAINumerology", "XRAIIdentityTime"]
        ),
        // P02 vault: pure contracts (stdlib only) and the only CryptoKit adapter.
        .target(
            name: "XRAIVaultContracts",
            dependencies: []
        ),
        .target(
            name: "XRAIVaultCryptoKit",
            dependencies: ["XRAIVaultContracts"]
        ),
        // Development/test doubles (in-memory keys, consent registry, manual clock).
        // RULE: no non-test target may ever depend on XRAIVaultTesting (test-enforced).
        .target(
            name: "XRAIVaultTesting",
            dependencies: ["XRAIVaultContracts"]
        ),
        .testTarget(
            name: "XRAIVaultTests",
            dependencies: ["XRAIVaultContracts", "XRAIVaultCryptoKit", "XRAIVaultTesting"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
