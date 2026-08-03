// swift-tools-version: 5.9
import PackageDescription

// OrainCore — the pure, testable heart of Òrain for iOS.
//
// Deliberately has NO dependency on SwiftUI, SwiftData, UIKit or Foundation's
// heavier corners, so it builds and tests from the Terminal with
//   swift test
// on the Mac without opening Xcode. Everything that can be proved correct
// without a simulator lives here.

let package = Package(
    name: "OrainCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "OrainCore", targets: ["OrainCore"]),
    ],
    targets: [
        .target(name: "OrainCore"),
        .testTarget(
            name: "OrainCoreTests",
            dependencies: ["OrainCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
