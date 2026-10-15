// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MacAuthenticator",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacAuthenticator", targets: ["MacAuthenticator"])],
    targets: [
        .target(name: "AuthenticatorCore"),
        .executableTarget(name: "MacAuthenticator", dependencies: ["AuthenticatorCore"]),
        .executableTarget(name: "AuthenticatorChecks", dependencies: ["AuthenticatorCore"], path: "Tests/AuthenticatorCoreTests", exclude: ["Fixtures"])
    ],
    swiftLanguageModes: [.v5]
)
