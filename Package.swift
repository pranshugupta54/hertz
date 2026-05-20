// swift-tools-version:6.2
import PackageDescription

let isolation: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Hertz",
    platforms: [.macOS(.v14)],
    targets: [
        // Shared metric collectors — used by both the app and the verifier,
        // so the verifier checks the exact code the app runs.
        .target(
            name: "HertzCore",
            path: "Sources/HertzCore",
            swiftSettings: isolation
        ),
        // The menu-bar app. This is the only product that ships.
        .executableTarget(
            name: "Hertz",
            dependencies: ["HertzCore"],
            path: "Sources/Hertz",
            swiftSettings: isolation
        ),
        // Dev-only verification — run `swift run HertzVerify`. A separate
        // product; never bundled into the shipped Hertz app.
        .executableTarget(
            name: "HertzVerify",
            dependencies: ["HertzCore"],
            path: "Sources/HertzVerify",
            swiftSettings: isolation
        )
    ]
)
