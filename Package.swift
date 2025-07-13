// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "Vaporized",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Vaporized",
            targets: ["Vaporized"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/leviouwendijk/plate.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Structures.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Extensions.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Interfaces.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Surfaces.git",
            branch: "master"
        ),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "Vaporized",
            dependencies: [
                .product(name: "plate", package: "plate"),
                .product(name: "Structures", package: "Structures"),
                .product(name: "Extensions", package: "Extensions"),
                .product(name: "Interfaces", package: "Interfaces"),
                .product(name: "Surfaces", package: "Surfaces"),
                // .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "JWTKit", package: "jwt-kit"),
            ],
            resources: [
                .process("Resources")
            ],
        ),
        .testTarget(
            name: "VaporizedTests",
            dependencies: [
                "Vaporized",
                .product(name: "plate", package: "plate"),
                .product(name: "Structures", package: "Structures"),
                .product(name: "Extensions", package: "Extensions"),
                .product(name: "Interfaces", package: "Interfaces"),
                .product(name: "Surfaces", package: "Surfaces"),
                // .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "JWTKit", package: "jwt-kit"),
            ]
        ),
    ]
)
