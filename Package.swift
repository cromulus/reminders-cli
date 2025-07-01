// swift-tools-version:5.9
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
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", .upToNextMinor(from: "1.8.2")),
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
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            swiftSettings: [
                .define("PRIVATE_REMINDERS_ENABLED", .when(configuration: .debug))
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
