// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "reminders",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .executable(name: "reminders", targets: ["reminders"]),
        .executable(name: "reminders-api", targets: ["reminders-api"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.3.1")),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "1.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "reminders",
            dependencies: ["RemindersLibrary"]
        ),
        .executableTarget(
            name: "reminders-api",
            dependencies: [
                "RemindersLibrary",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdFoundation", package: "hummingbird"),
            ]
        ),
        .target(
            name: "RemindersLibrary",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "RemindersTests",
            dependencies: [
                "RemindersLibrary",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdFoundation", package: "hummingbird"),
            ]
        ),
    ]
)
