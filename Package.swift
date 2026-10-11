// swift-tools-version: 6.1
import PackageDescription

// Tests build as an executable (`swift run inbox-tests`) because with only the Command Line
// Tools installed, `swift test` builds the bundle but its runner discovers no swift-testing
// tests. The CLT also keep swift-testing outside the default search paths.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltLibs = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let package = Package(
    name: "ContextInbox",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ContextInbox", targets: ["ContextInbox"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "InboxCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "ContextInbox",
            dependencies: ["InboxCore"]
        ),
        .executableTarget(
            name: "inbox-tests",
            dependencies: ["InboxCore"],
            path: "Tests/InboxCoreTests",
            swiftSettings: [.unsafeFlags(["-F", cltFrameworks])],
            linkerSettings: [.unsafeFlags(["-F", cltFrameworks, "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
                                            "-Xlinker", "-rpath", "-Xlinker", cltLibs])]
        ),
    ]
)
