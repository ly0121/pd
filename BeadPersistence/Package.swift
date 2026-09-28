// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "BeadPersistence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BeadPersistence", targets: ["BeadPersistence"]),
    ],
    dependencies: [
        .package(path: "../BeadCore"),
    ],
    targets: [
        .target(
            name: "BeadPersistence",
            dependencies: [.product(name: "BeadCore", package: "BeadCore")]
        ),
        .testTarget(
            name: "BeadPersistenceTests",
            dependencies: ["BeadPersistence"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
