// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "reminders",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "reminders", targets: ["reminders"]),
        .executable(name: "reminders-api", targets: ["reminders-api"]),
        .executable(name: "reminders-mcp", targets: ["reminders-mcp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.3.1")),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", .upToNextMinor(from: "1.8.2")),
        .package(url: "https://github.com/Cocoanetics/SwiftMCP.git", branch: "main"),
        .package(url: "https://github.com/swift-server/async-http-client.git", .upToNextMinor(from: "1.17.0"))
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
                "RemindersMCPKit",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdFoundation", package: "hummingbird"),
                .product(name: "SwiftMCP", package: "SwiftMCP"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ]
        ),
        .executableTarget(
            name: "reminders-mcp",
            dependencies: [
                "RemindersMCPKit",
                .product(name: "SwiftMCP", package: "SwiftMCP"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "RemindersLibrary"
            ]
        ),
        .target(
            name: "RemindersMCPKit",
            dependencies: [
                "RemindersLibrary",
                .product(name: "SwiftMCP", package: "SwiftMCP"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "AsyncHTTPClient", package: "async-http-client")
            ]
        ),
        .target(
            name: "RemindersLibrary",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Hummingbird", package: "hummingbird"),
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
