// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NCCore",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "NCCore", targets: ["NCCore"])
    ],
    targets: [
        // Pure-Swift logic layer: no AppKit dependency. Used as a local
        // package dependency of the Biruni app target - kept separate so
        // the filesystem/archive/compare/menu logic stays testable in
        // isolation from the UI layer, the same split the original
        // NortonCommanderMac SwiftPM project used.
        .target(
            name: "NCCore",
            path: "Sources/NCCore"
        )
    ]
)
