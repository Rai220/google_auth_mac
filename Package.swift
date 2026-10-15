// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MacAuthenticator",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacAuthenticator", targets: ["MacAuthenticator"])],
    targets: [
        .target(name: "AuthenticatorCore"),
        .target(name: "AuthenticatorState", dependencies: ["AuthenticatorCore"]),
        .executableTarget(name: "MacAuthenticator", dependencies: ["AuthenticatorCore", "AuthenticatorState"]),
        .executableTarget(name: "AuthenticatorStateChecks", dependencies: ["AuthenticatorState"], path: "Tests/AuthenticatorStateChecks"),
        .executableTarget(name: "AuthenticatorChecks", dependencies: ["AuthenticatorCore"], path: "Tests/AuthenticatorCoreTests", exclude: ["Fixtures"])
    ],
    swiftLanguageModes: [.v5]
)
